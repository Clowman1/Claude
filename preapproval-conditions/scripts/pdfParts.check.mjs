// Check for lwc/leadBorrowerPortalDocumentRow/pdfParts.js, run against the shipped library:
//   node scripts/pdfParts.check.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { splitPdf, partName } from '../force-app/main/default/lwc/leadBorrowerPortalDocumentRow/pdfParts.js';

const PDFLib = createRequire(import.meta.url)('../force-app/main/default/staticresources/pdfLib.js');
const LIMIT = 3_500_000;

// pdf-lib reads only the SOF header of a JPEG, so random bytes after it stand in for an
// incompressible scan of any size.
function fakeJpeg(bytes) {
    const header = [0xff, 0xd8, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x04, 0x00, 0x03, 0x00, 0x03,
        0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01];
    const body = new Uint8Array(bytes);
    for (let i = 0; i < body.length; i++) body[i] = Math.floor(Math.random() * 255);
    return new Uint8Array([...header, ...body]);
}

async function makePdf(pageImageSizes) {
    const doc = await PDFLib.PDFDocument.create();
    for (const [index, size] of pageImageSizes.entries()) {
        // Width encodes the original page number so order can be checked after splitting.
        const page = doc.addPage([300 + index, 400]);
        page.drawImage(await doc.embedJpg(fakeJpeg(size)), { x: 0, y: 0, width: 10, height: 10 });
    }
    return doc.save();
}

async function widths(parts) {
    const all = [];
    for (const bytes of parts) {
        assert.ok(bytes.length <= LIMIT, `part of ${bytes.length} bytes is over the limit`);
        const doc = await PDFLib.PDFDocument.load(bytes);
        doc.getPages().forEach(page => all.push(page.getWidth()));
    }
    return all;
}

const calls = [];
const rasterize = async (bytes, pageNumbers) => {
    calls.push(pageNumbers);
    const doc = await PDFLib.PDFDocument.create();
    const count = pageNumbers ? pageNumbers.length : 3;
    for (let i = 0; i < count; i++) doc.addPage([pageNumbers ? 300 + pageNumbers[i] - 1 : 300 + i, 400]);
    return doc;
};

// 1. A long statement: every page copied, all parts under the limit, order kept.
const statement = await makePdf(Array(20).fill(400_000));
const parts = await splitPdf(statement, LIMIT, { PDFLib, rasterize });
assert.ok(parts.length >= 3, `expected several parts, got ${parts.length}`);
assert.deepEqual(await widths(parts), Array.from({ length: 20 }, (u, i) => 300 + i));
assert.equal(calls.length, 0, 'nothing should be rendered when every page fits');

// 2. One scan bigger than the limit on its own: only that page is rendered, and the light
// pages after it are grouped again rather than each becoming a file.
const mixed = await makePdf([200_000, 5_000_000, ...Array(8).fill(100_000)]);
const mixedParts = await splitPdf(mixed, LIMIT, { PDFLib, rasterize });
assert.deepEqual(calls, [[2]]);
assert.deepEqual(await widths(mixedParts), Array.from({ length: 10 }, (u, i) => 300 + i));
assert.ok(mixedParts.length <= 5, `light pages were not regrouped: ${mixedParts.length} parts`);

// 3. Something pdf-lib cannot open (an encrypted statement): the whole file is rendered.
calls.length = 0;
await splitPdf(new Uint8Array([1, 2, 3]), LIMIT, { PDFLib, rasterize });
assert.deepEqual(calls, [null]);

assert.equal(partName('May Statement.PDF', 1, 3), 'May Statement (part 2 of 3).pdf');
console.log(`ok - ${parts.length} parts from the statement, sizes ${parts.map(p => p.length).join(', ')}`);
