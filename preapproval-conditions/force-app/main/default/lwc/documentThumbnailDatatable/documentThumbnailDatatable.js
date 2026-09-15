import LightningDatatable from 'lightning/datatable';
import thumbnailCell from './thumbnailCell.html';

/**
 * The stock datatable has no image cell, so the document list could only ever show a file name and
 * a type icon. This adds one column type - a thumbnail of the file itself - and nothing else.
 */
export default class DocumentThumbnailDatatable extends LightningDatatable {
    static customTypes = {
        thumbnail: {
            template: thumbnailCell,
            standardCellLayout: true,
            typeAttributes: ['alt', 'fallbackIcon']
        }
    };
}
