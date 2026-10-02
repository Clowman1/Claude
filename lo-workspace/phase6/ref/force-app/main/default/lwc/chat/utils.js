import TIME_ZONE from "@salesforce/i18n/timeZone";
import LOCALE from "@salesforce/i18n/locale";

/**
 *********************************************************
 * @name                 : utils
 * @date                 : 06.03.2025
 * @description          :
 * @author               : Taras Babyn
 * @change log           : Mar 06, 2025 Taras Babyn - Initial Version
 *********************************************************
 */
export function formatDatetime(value) {
    const options = {
        timeZone: TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
    };
    return !!value ? new Intl.DateTimeFormat(LOCALE, options).format(new Date(value)) : '';
}