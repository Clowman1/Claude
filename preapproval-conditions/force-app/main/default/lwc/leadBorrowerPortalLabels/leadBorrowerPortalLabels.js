/**
 * Borrower-facing wording for the document portal.
 *
 * A plain dictionary rather than Custom Labels: one language, one component, and 45 label records
 * plus a translation file would be a lot of metadata to carry for the same result. If a third
 * language ever arrives this converts to labels mechanically.
 *
 * Formal register throughout (usted), and no gendered constructions - the borrower's gender is not
 * knowable from the record, so nothing may require agreement.
 */
const ES = {
    'Welcome Back': 'Le damos la bienvenida',
    'You can manage your documents here': 'Aquí puede administrar sus documentos',
    'Documents Needed': 'Documentos Pendientes',
    'Documents Uploaded': 'Documentos Subidos',
    'Documents Approved': 'Documentos Aprobados',
    'Documents Required': 'Documentos Requeridos',
    'The documents requested below help your loan team keep your file moving before your loan is converted to a transaction.':
        'Los documentos solicitados a continuación ayudan a su equipo hipotecario a seguir avanzando con su expediente antes de que su préstamo pase a ser una transacción.',

    'Document Name': 'Nombre del Documento',
    'Document Description': 'Descripción del Documento',
    Status: 'Estado',
    Actions: 'Acciones',

    Needed: 'Pendiente',
    Requested: 'Solicitado',
    'In Progress': 'En Proceso',
    'Ready to submit': 'Listo para Enviar',
    'Submitted for review': 'Enviado para Revisión',
    Accepted: 'Aceptado',
    Approved: 'Aprobado',
    Cleared: 'Completado',
    Completed: 'Completado',
    'More needed': 'Se Necesita Más',
    'Uploading...': 'Subiendo...',

    'Drag a file here, or browse': 'Arrastre un archivo aquí, o búsquelo',
    'Add another file': 'Agregar otro archivo',
    Remove: 'Quitar',
    'Remove this file': 'Quitar este archivo',
    'Added. Press Submit above when you have added everything.':
        'Agregado. Presione Enviar arriba cuando haya agregado todo.',

    'Upload everything, then press Submit': 'Suba todo y luego presione Enviar',
    'Add as many documents as you like - take your time and come back if you need to. Your loan team is not notified until you press Submit Docs for Review, so please remember to press it when you have finished.':
        'Agregue todos los documentos que desee: tómese su tiempo y regrese si lo necesita. Su equipo hipotecario no recibe aviso hasta que usted presione Enviar Documentos para Revisión, así que recuerde presionarlo cuando haya terminado.',

    'Submit Docs for Review': 'Enviar Documentos para Revisión',
    'Your loan team has not been notified yet.': 'Su equipo hipotecario aún no ha sido notificado.',
    'Documents Submitted for Review': 'Documentos Enviados para Revisión',
    'Your loan team has been notified and will review them shortly.':
        'Su equipo hipotecario ha sido notificado y los revisará en breve.',
    Dismiss: 'Cerrar',
    'Hide completed': 'Ocultar completados',

    'Upload Failed': 'Error al Subir',
    'Your upload could not be processed. Please try again or contact your loan team.':
        'No se pudo procesar su archivo. Intente de nuevo o comuníquese con su equipo hipotecario.',
    'File Upload Complete': 'Archivo Subido',
    'Your file(s) have been successfully uploaded.': 'Sus archivos se subieron correctamente.',
    'Something went wrong uploading that file. Please try again.':
        'Ocurrió un problema al subir ese archivo. Intente de nuevo.',
    'We could not save that file. Please try again, or email it to your loan team.':
        'No pudimos guardar ese archivo. Intente de nuevo o envíelo por correo a su equipo hipotecario.',
    'That file could not be read.': 'No se pudo leer ese archivo.',

    'Loan Officer': 'Oficial de Préstamos',
    'Loan Partner': 'Asistente de Préstamos'
};

/** The English is the key, so an untranslated string falls through as itself rather than blank. */
export function t(english, spanish) {
    if (!spanish) {
        return english;
    }
    return ES[english] || english;
}

export function documentsReadyToSend(count, spanish) {
    if (!spanish) {
        return count === 1 ? '1 document ready to send' : `${count} documents ready to send`;
    }
    return count === 1 ? '1 documento listo para enviar' : `${count} documentos listos para enviar`;
}

export function showCompleted(count, spanish) {
    if (!spanish) {
        return `Show ${count} completed ${count === 1 ? 'document' : 'documents'}`;
    }
    return `Mostrar ${count} ${count === 1 ? 'documento completado' : 'documentos completados'}`;
}

export function submitButton(count, spanish) {
    return `${t('Submit Docs for Review', spanish)} (${count})`;
}

export function uploadingOne(fileName, spanish) {
    return spanish ? `Subiendo ${fileName}...` : `Uploading ${fileName}...`;
}

export function uploadingMany(index, total, spanish) {
    return spanish ? `Subiendo ${index} de ${total}...` : `Uploading ${index} of ${total}...`;
}

// Long PDFs are split automatically, so this now means a large non-PDF (a Word file, a video) or
// a PDF that could not be split.
export function tooLarge(fileName, spanish) {
    return spanish
        ? `${fileName} es demasiado grande para subirlo aquí. Envíelo por correo a su equipo hipotecario.`
        : `${fileName} is too large to upload here. Please email it to your loan team.`;
}

export function passwordProtected(fileName, spanish) {
    return spanish
        ? `${fileName} está protegido con contraseña, así que no podemos abrirlo. Guarde una copia sin contraseña ` +
          `y agréguela de nuevo, o envíelo por correo a su equipo hipotecario.`
        : `${fileName} is password-protected, so we cannot open it. Please save a copy without the password and ` +
          `add it again, or email it to your loan team.`;
}

export function preparing(fileName, spanish) {
    return spanish ? `Preparando ${fileName}...` : `Preparing ${fileName}...`;
}

export function tooSmall(fileName, width, height, spanish) {
    return spanish
        ? `${fileName} llegó con un tamaño de ${width} x ${height} píxeles. Normalmente es demasiado pequeño para poder leerlo. `
            + 'Si su teléfono le pidió elegir un tamaño al adjuntarlo, elija Tamaño Real o Grande y agréguelo de nuevo.'
        : `${fileName} came through at ${width} x ${height} pixels. That is usually too small for us to read. `
            + 'If your phone asked you to pick a size when you attached it, choose Actual Size or Large and add it again.';
}