/**
 * @author Uptima
 * @date 2026-09-19
 * @group Utilities
 * @description Shared platform helpers for Aura controllers (Id validation, Aura exceptions, picklists).
 *              Inherited sharing so DML helpers keep the caller's sharing mode.
 */
public inherited sharing class PlatformUtilities {
	/**
	 * @description Label/value pair for Aura-enabled picklist UIs.
	 */
	public class PicklistOption {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;
	}

	/**
	 * @description Returns true when value is a 15- or 18-character Salesforce Id that Id.valueOf accepts.
	 * @param value Candidate Id string
	 * @return true when value is a valid Salesforce Id
	 */
	public static Boolean isSalesforceId(String value) {
		if (
			String.isBlank(value) ||
			(value.length() != 15 &&
			value.length() != 18)
		) {
			return false;
		}
		try {
			Id.valueOf(value);
			return true;
		} catch (Exception e) {
			return false;
		}
	}

	/**
	 * @description Builds an AuraHandledException with a user-visible message.
	 * @param message Message shown to the Lightning client
	 * @return AuraHandledException
	 */
	public static AuraHandledException buildAuraException(String message) {
		AuraHandledException ex = new AuraHandledException(message);
		ex.setMessage(message);
		return ex;
	}

	/**
	 * @description Resolves a readable exception message, preferring the cause when present.
	 * @param e Exception to inspect
	 * @return Message string, or null when e is null
	 */
	public static String resolveExceptionMessage(Exception e) {
		if (e == null) {
			return null;
		}
		if (
			e.getCause() != null && String.isNotBlank(e.getCause().getMessage())
		) {
			return e.getCause().getMessage();
		}
		return e.getMessage();
	}

	/**
	 * @description GW-2707: Exception to throw from an @AuraEnabled method. An AuraHandledException (a message for
	 *              the user) is returned as it is; any other exception becomes one with its readable message.
	 * @param e Exception caught in the @AuraEnabled method
	 * @return AuraHandledException
	 * @example
	 * } catch (Exception e) {
	 * 	throw PlatformUtilities.toAuraException(e);
	 * }
	 */
	public static AuraHandledException toAuraException(Exception e) {
		return e instanceof AuraHandledException
			? (AuraHandledException) e
			: buildAuraException(resolveExceptionMessage(e));
	}

	/**
	 * @description Returns active picklist entries for a field as Aura picklist options.
	 * @param fieldToken SObject field token
	 * @return Active picklist options
	 */
	public static List<PicklistOption> getActivePicklistOptions(
		Schema.SObjectField fieldToken
	) {
		List<PicklistOption> options = new List<PicklistOption>();
		if (fieldToken == null) {
			return options;
		}
		for (
			Schema.PicklistEntry entry : fieldToken.getDescribe()
				.getPicklistValues()
		) {
			if (!entry.isActive()) {
				continue;
			}
			PicklistOption option = new PicklistOption();
			option.label = entry.getLabel();
			option.value = entry.getValue();
			options.add(option);
		}
		return options;
	}

	/**
	 * @description Returns Yes/No options for boolean-style Aura picklists.
	 * @return Yes and No picklist options
	 */
	public static List<PicklistOption> buildYesNoOptions() {
		List<PicklistOption> options = new List<PicklistOption>();
		PicklistOption yesOption = new PicklistOption();
		yesOption.label = 'Yes';
		yesOption.value = 'Yes';
		options.add(yesOption);
		PicklistOption noOption = new PicklistOption();
		noOption.label = 'No';
		noOption.value = 'No';
		options.add(noOption);
		return options;
	}

	/**
	 * @description Returns the value at the given key as a Map<String, Object>, or null if
	 *              the source map is null, the key is absent, or the value isn't a map.
	 * @param source The map to read from.
	 * @param key The key to look up.
	 * @return The value as a Map<String, Object>, or null.
	 */
	public static Map<String, Object> getMapValue(
		Map<String, Object> source,
		String key
	) {
		if (source == null || !source.containsKey(key)) {
			return null;
		}

		Object value = source.get(key);
		return value instanceof Map<String, Object>
			? (Map<String, Object>) value
			: null;
	}

	/**
	 * @description Returns the value at the given key as a List<Object>, or null if the
	 *              source map is null, the key is absent, or the value isn't a list.
	 * @param source The map to read from.
	 * @param key The key to look up.
	 * @return The value as a List<Object>, or null.
	 */
	public static List<Object> getListValue(
		Map<String, Object> source,
		String key
	) {
		if (source == null || !source.containsKey(key)) {
			return null;
		}

		Object value = source.get(key);
		return value instanceof List<Object> ? (List<Object>) value : null;
	}

	/**
	 * @description Returns the first non-blank string, otherwise the second value.
	 * @param first Preferred value
	 * @param second Fallback value
	 * @return first when non-blank, otherwise second
	 */
	public static String firstNonBlank(String first, String second) {
		return String.isNotBlank(first) ? first : second;
	}

	/**
	 * @description Returns the first non-blank string among three values.
	 * @param first Preferred value
	 * @param second Second choice
	 * @param third Fallback value
	 * @return First non-blank value, or third when the others are blank
	 */
	public static String firstNonBlank(
		String first,
		String second,
		String third
	) {
		if (String.isNotBlank(first)) {
			return first;
		}
		return firstNonBlank(second, third);
	}

	/**
	 * @description Formats a percent for display. Blank when the amount is null or zero.
	 * @param amount Percent amount
	 * @return Plain number plus a percent sign, or an empty string
	 */
	public static String formatPercent(Decimal amount) {
		if (amount == null || amount == 0) {
			return '';
		}
		return amount.stripTrailingZeros().toPlainString() + '%';
	}

	/**
	 * @description Trims a string and returns null in place of an empty or blank result,
	 *              so callers can treat "no value" and "blank value" the same way.
	 * @param value The string to trim.
	 * @return The trimmed string, or null if it is null or blank after trimming.
	 */
	public static String trimToNull(String value) {
		if (value == null) {
			return null;
		}

		String trimmed = value.trim();
		return String.isBlank(trimmed) ? null : trimmed;
	}

	/**
	 * @description Parses a string as a Salesforce Id, returning null instead of throwing
	 *              if the value is blank or not a valid Id.
	 * @param value The string to parse.
	 * @return The parsed Id, or null if it is blank or invalid.
	 */
	public static Id parseId(String value) {
		if (String.isBlank(value)) {
			return null;
		}

		try {
			return (Id) value;
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @description Parses a list of Id values from an untyped JSON list.
	 * @param value Untyped list (typically from JSON.deserializeUntyped)
	 * @return Parsed Ids; blank/invalid entries are skipped
	 */
	public static List<Id> parseIdList(Object value) {
		List<Id> ids = new List<Id>();
		if (!(value instanceof List<Object>)) {
			return ids;
		}
		for (Object rawValue : (List<Object>) value) {
			Id parsedId = parseId(String.valueOf(rawValue));
			if (parsedId != null) {
				ids.add(parsedId);
			}
		}
		return ids;
	}

	/**
	 * @description Coerces common JSON/boolean representations to Boolean.
	 * @param value Boolean, or string/number representation
	 * @return true for true/1/yes (case-insensitive); otherwise false
	 */
	public static Boolean toBoolean(Object value) {
		if (value == null) {
			return false;
		}
		if (value instanceof Boolean) {
			return (Boolean) value;
		}
		String text = String.valueOf(value);
		return 'true'.equalsIgnoreCase(text) ||
			'1'.equals(text) ||
			'yes'.equalsIgnoreCase(text);
	}

	/**
	 * @description Parses a positive Decimal from common JSON numeric types.
	 * @param value Decimal/Integer/Long/String value
	 * @param defaultValue Value returned when null/blank/non-positive
	 * @return Parsed positive Decimal, or defaultValue
	 */
	public static Decimal parsePositiveDecimal(
		Object value,
		Decimal defaultValue
	) {
		if (value == null) {
			return defaultValue;
		}
		if (value instanceof Decimal) {
			Decimal decimalValue = (Decimal) value;
			return decimalValue > 0 ? decimalValue : defaultValue;
		}
		if (value instanceof Integer) {
			Integer intValue = (Integer) value;
			return intValue > 0 ? Decimal.valueOf(intValue) : defaultValue;
		}
		if (value instanceof Long) {
			Long longValue = (Long) value;
			return longValue > 0 ? Decimal.valueOf(longValue) : defaultValue;
		}

		String text = String.valueOf(value);
		if (String.isBlank(text)) {
			return defaultValue;
		}

		Decimal parsed = Decimal.valueOf(text);
		return parsed > 0 ? parsed : defaultValue;
	}

	/**
	 * @description Serializes the given body to JSON and writes it to the REST response
	 *              along with the given HTTP status code.
	 * @param response The REST response to write to.
	 * @param statusCode The HTTP status code to set on the response.
	 * @param body The map to serialize as the response body.
	 */
	public static void writeJson(
		RestResponse response,
		Integer statusCode,
		Map<String, Object> body
	) {
		response.statusCode = statusCode;
		response.responseBody = Blob.valueOf(JSON.serialize(body));
	}

	/**
	 * @description GW-5874 - Reduces a North American phone number to its 10 digits: strips formatting and the
	 *              +1 country code, so '+1 (555) 123-4567' becomes '5551234567'.
	 * @param phone Raw phone number
	 * @return Digits only, or null when the value has no digits
	 */
	public static String normalizePhone(String phone) {
		if (String.isBlank(phone)) {
			return null;
		}

		String digits = phone.replaceAll('[^0-9]', '');
		if (digits.length() == 11 && digits.startsWith('1')) {
			digits = digits.substring(1);
		}
		return String.isBlank(digits) ? null : digits;
	}

	/**
	 * @description Null-safe uppercase for print/label payloads (used by PrinterService).
	 * @param value Input string
	 * @return Uppercased value, or the original blank/null value
	 */
	public static String toUpperCase(String value) {
		return String.isBlank(value) ? value : value.toUpperCase();
	}

	/**
	 * @description Converts null to empty string for print/map payloads (used by PrinterService).
	 * @param value Input string
	 * @return Empty string when null; otherwise the original value
	 */
	public static String blankToEmpty(String value) {
		return value == null ? '' : value;
	}

	/**
	 * @description Updates records with partial success and returns the first error message
	 *              for each record that failed. Sharing follows the calling class.
	 * @param recordList Records to update; each must have an Id
	 * @param accessLevel USER_MODE or SYSTEM_MODE
	 * @return First error message by record Id; empty when every record saved
	 */
	public static Map<Id, String> updateAllowingPartialSuccess(
		List<SObject> recordList,
		AccessLevel accessLevel
	) {
		Map<Id, String> errorMessageById = new Map<Id, String>();
		if (recordList == null || recordList.isEmpty()) {
			return errorMessageById;
		}

		List<Database.SaveResult> saveResultList = Database.update(
			recordList,
			false,
			accessLevel
		);
		for (Integer index = 0; index < saveResultList.size(); index++) {
			Database.SaveResult saveResult = saveResultList[index];
			if (!saveResult.isSuccess()) {
				errorMessageById.put(
					recordList[index].Id,
					saveResult.getErrors()[0].getMessage()
				);
			}
		}
		return errorMessageById;
	}

	/**
	 * @description GW-6099 - Logs every failed row of a partial-success DML (allOrNone = false) as a Nebula ERROR
	 *              against its record. The caller saves the log.
	 * @param records Records passed to the DML, in the same order as saveResults
	 * @param saveResults Results of Database.insert/update(records, false, ...)
	 * @return Number of failed rows
	 * @example
	 * Integer failedCount = PlatformUtilities.logSaveFailures(records, Database.update(records, false));
	 */
	public static Integer logSaveFailures(
		List<SObject> records,
		List<Database.SaveResult> saveResults
	) {
		Integer failedCount = 0;
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (saveResults[i].isSuccess()) {
				continue;
			}
			failedCount++;
			List<String> messages = new List<String>();
			for (Database.Error error : saveResults[i].getErrors()) {
				messages.add(error.getMessage());
			}
			Logger.error(
					new LogMessage(
						'Save failed for {0}: {1}',
						records[i].Id,
						String.join(messages, '; ')
					)
				)
				.setRecord(records[i]);
		}
		return failedCount;
	}

	/**
	 * @description GW-2706: Joins values into one CSV line. Null becomes an empty cell; a value containing a comma,
	 *              quote or line break is quoted, with its quotes doubled.
	 * @param values Cell values in column order
	 * @return CSV line without a line break
	 * @example
	 * String line = PlatformUtilities.toCsvLine(new List<String>{ 'Row 2', 'Invalid zone, "Z1"' });
	 */
	public static String toCsvLine(List<String> values) {
		List<String> cells = new List<String>();
		for (String value : values) {
			cells.add(
				value?.containsAny(',"\n\r') == true
					? '"' + value.replace('"', '""') + '"'
					: (value ?? '')
			);
		}
		return String.join(cells, ',');
	}

	/**
	 * @description GW-2707: First day of the next fiscal year after the given date, from the org's fiscal year
	 *              start month. On the start day itself, the following year's start is returned.
	 * @param fromDate Date to count from
	 * @return Start date of the next fiscal year
	 * @example
	 * Date nextStart = PlatformUtilities.nextFiscalYearStart(Date.today());
	 */
	public static Date nextFiscalYearStart(Date fromDate) {
		Organization org = (Organization) SoqlQueryBuilder.fromObject('Organization')
			.selectField('FiscalYearStartMonth')
			.first();
		Date startDate = Date.newInstance(fromDate.year(), org.FiscalYearStartMonth, 1);
		return fromDate < startDate ? startDate : startDate.addYears(1);
	}
}