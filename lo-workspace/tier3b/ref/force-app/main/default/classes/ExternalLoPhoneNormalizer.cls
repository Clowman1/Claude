public with sharing class ExternalLoPhoneNormalizer {
    public static String digits(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String value = phone.replaceAll('[^0-9]', '');
        return String.isBlank(value) ? null : value;
    }

    public static String matchKey(String phone) {
        String value = digits(phone);
        if (value == null) {
            return null;
        }
        if (value.length() == 11 && value.startsWith('1')) {
            value = value.substring(1);
        }
        return value;
    }

    public static Set<String> soqlVariants(Set<String> phones) {
        Set<String> variants = new Set<String>();
        if (phones == null || phones.isEmpty()) {
            return variants;
        }
        for (String phone : phones) {
            variants.addAll(soqlVariants(phone));
        }
        return variants;
    }

    public static Set<String> soqlVariants(String phone) {
        Set<String> variants = new Set<String>();
        if (String.isBlank(phone)) {
            return variants;
        }
        variants.add(phone.trim());
        String key = matchKey(phone);
        if (key == null) {
            return variants;
        }
        variants.add(key);
        if (key.length() != 10) {
            return variants;
        }
        String area = key.substring(0, 3);
        String prefix = key.substring(3, 6);
        String line = key.substring(6);
        variants.add(area + '-' + prefix + '-' + line);
        variants.add('(' + area + ') ' + prefix + '-' + line);
        variants.add(area + '.' + prefix + '.' + line);
        variants.add(area + ' ' + prefix + ' ' + line);
        variants.add('1' + key);
        variants.add('+1' + key);
        variants.add('1-' + area + '-' + prefix + '-' + line);
        variants.add('+1 ' + area + '-' + prefix + '-' + line);
        return variants;
    }
}