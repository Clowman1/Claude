/**
 * Cuts a PDF that is over the upload limit into parts that each fit under it.
 *
 * Pages are copied untouched wherever possible, so text stays selectable and nothing is degraded.
 * A page is rendered to an image only when it cannot fit on its own (one huge scan), and a whole
 * file only when pdf-lib cannot open it - which in practice means a bank statement carrying an
 * owner-password restriction. pdf.js can read those; pdf-lib cannot.
 *
 * The libraries are passed in rather than read from window so this file runs under Node for its
 * check (pdfParts.check.mjs, kept outside force-app).
 */

// Longest edge of a rendered page. A letter page at this size is about 200 dpi: a statement
// stays legible and the JPEG comes out well under 1 MB.
const RASTER_EDGE = 2200;
const RASTER_QUALITY = 0.8;
// Headroom for the guess at how many pages fit: copied pages each carry their own fonts, so a
// part is a little heavier than its share of the original.
const FILL_TARGET = 0.9;

export class PdfPartsError extends Error {
    constructor(reason) {
        super(reason);
        this.reason = reason;
    }
}

/**
 * Returns an array of Uint8Array, each a complete PDF of at most maxBytes, in page order.
 * rasterize(bytes, pageNumbers) must return a PDFDocument of image pages; see rasterizePages.
 */
export async function splitPdf(bytes, maxBytes, { PDFLib, rasterize }) {
    let source;
    try {
        source = await PDFLib.PDFDocument.load(bytes);
    } catch (loadError) {
        source = null;
    }
    if (!source) {
        // Every page as an image; each then fits on its own, and the packing below groups them.
        source = await rasterize(bytes, null);
    }
    return packPages(source, bytes, maxBytes, PDFLib, rasterize);
}

async function packPages(source, originalBytes, maxBytes, PDFLib, rasterize) {
    const total = source.getPageCount();
    const bytesPerPage = originalBytes.length / Math.max(total, 1);
    let pagesPerPart = Math.max(1, Math.floor((maxBytes * FILL_TARGET) / bytesPerPage));
    const parts = [];
    let start = 0;

    while (start < total) {
        let count = Math.min(pagesPerPart, total - start);
        let partBytes = await copyPages(PDFLib, source, start, count);
        while (partBytes.length > maxBytes && count > 1) {
            count = Math.max(1, Math.min(count - 1, Math.floor((count * maxBytes * FILL_TARGET) / partBytes.length)));
            partBytes = await copyPages(PDFLib, source, start, count);
        }
        if (partBytes.length > maxBytes) {
            // One page over the limit by itself. Only reachable for an untouched page: a rendered
            // one is far smaller, and the original bytes are what pdf.js needs to render it.
            const rendered = await rasterize(originalBytes, [start + 1]);
            partBytes = await rendered.save({ useObjectStreams: true });
            if (partBytes.length > maxBytes) {
                throw new PdfPartsError('page-too-large');
            }
        }
        parts.push(partBytes);
        start += count;
        // A part well under the limit means the guess was dragged down by one heavy page; let it
        // recover, or every page after a big scan becomes its own file.
        pagesPerPart = partBytes.length < maxBytes / 2 ? count * 2 : count;
    }
    return parts;
}

async function copyPages(PDFLib, source, start, count) {
    const part = await PDFLib.PDFDocument.create();
    const indices = Array.from({ length: count }, (unused, offset) => start + offset);
    const pages = await part.copyPages(source, indices);
    pages.forEach(page => part.addPage(page));
    return part.save({ useObjectStreams: true });
}

/**
 * Renders pages to JPEG and returns them as a new PDFDocument at the original page sizes.
 * pageNumbers is 1-based; null means every page.
 */
export async function rasterizePages(bytes, pageNumbers, { PDFLib, pdfjsLib }) {
    let pdf;
    try {
        // pdf.js takes ownership of the buffer it is given, so it gets a copy.
        pdf = await pdfjsLib.getDocument({ data: bytes.slice(0), isEvalSupported: false }).promise;
    } catch (openError) {
        throw new PdfPartsError(openError?.name === 'PasswordException' ? 'password' : 'unreadable');
    }
    const output = await PDFLib.PDFDocument.create();
    const numbers = pageNumbers || Array.from({ length: pdf.numPages }, (unused, index) => index + 1);
    const canvas = document.createElement('canvas');
    try {
        for (const number of numbers) {
            // eslint-disable-next-line no-await-in-loop
            const page = await pdf.getPage(number);
            const natural = page.getViewport({ scale: 1 });
            const viewport = page.getViewport({
                scale: RASTER_EDGE / Math.max(natural.width, natural.height)
            });
            canvas.width = Math.round(viewport.width);
            canvas.height = Math.round(viewport.height);
            const context = canvas.getContext('2d');
            // JPEG has no transparency; an unpainted background would come out black.
            context.fillStyle = '#ffffff';
            context.fillRect(0, 0, canvas.width, canvas.height);
            // eslint-disable-next-line no-await-in-loop
            await page.render({ canvasContext: context, viewport }).promise;
            // eslint-disable-next-line no-await-in-loop
            const jpeg = await canvasToBytes(canvas);
            // eslint-disable-next-line no-await-in-loop
            const image = await output.embedJpg(jpeg);
            output
                .addPage([natural.width, natural.height])
                .drawImage(image, { x: 0, y: 0, width: natural.width, height: natural.height });
            page.cleanup();
        }
    } finally {
        // Releases the canvas memory now rather than whenever the collector gets to it; phones
        // run out quickly on a long statement.
        canvas.width = 0;
        canvas.height = 0;
        pdf.destroy();
    }
    return output;
}

function canvasToBytes(canvas) {
    return new Promise((resolve, reject) => {
        canvas.toBlob(
            blob => (blob ? blob.arrayBuffer().then(buffer => resolve(new Uint8Array(buffer)), reject) : reject(new PdfPartsError('unreadable'))),
            'image/jpeg',
            RASTER_QUALITY
        );
    });
}

/** "Statement.pdf" -> "Statement (part 2 of 3).pdf" */
export function partName(fileName, index, total) {
    const base = fileName.replace(/\.pdf$/i, '');
    return `${base} (part ${index + 1} of ${total}).pdf`;
}