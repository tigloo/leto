part of graphql_schema.src.schema;

/// `true` or `false`.
final GraphQLScalarType<bool, bool> graphQLBoolean = _GraphQLBoolType();

/// A UTF‐8 character sequence.
final GraphQLScalarType<String, String> graphQLString = _GraphQLStringType._();

/// The ID scalar type represents a unique identifier, often used to re-fetch
/// an object or as the key for a cache.
///
/// The ID type is serialized in the same way as a String; however, defining it
///  as an ID signifies that it is not intended to be human‐readable.
final GraphQLScalarType<String, String> graphQLId = _GraphQLStringType._('ID');

/// A [DateTime], serialized as an ISO-8601 string.
final GraphQLScalarType<DateTime, String> graphQLDate = _GraphQLDateType._();

/// A [DateTime], serialized as an UNIX timestamp.
final GraphQLScalarType<DateTime, int> graphQLTimestamp =
    _GraphQLTimestampType._();

/// A signed 32‐bit integer.
final GraphQLScalarType<int, int> graphQLInt = _GraphQLNumType(
  'Int',
  'A signed 64-bit integer.',
  'an integer',
);

/// A signed double-precision floating-point value.
final GraphQLScalarType<double, double> graphQLFloat = _GraphQLNumType(
  'Float',
  'A signed double-precision floating-point value.',
  'a float',
);

abstract class GraphQLScalarType<Value extends Object,
        Serialized extends Object> extends GraphQLType<Value, Serialized>
    with _NonNullableMixin<Value, Serialized> {
  // const GraphQLScalarType();

  String? get specifiedByURL => null;

  @override
  GraphQLType<Value, Serialized> coerceToInputObject() => this;
}

class _GraphQLBoolType extends GraphQLScalarType<bool, bool> {
  // const _GraphQLBoolType();

  @override
  bool serialize(bool value) {
    return value;
  }

  @override
  String get name => 'Boolean';

  @override
  String get description => 'A boolean value; can be either true or false.';

  @override
  ValidationResult<bool> validate(String key, Object? input) {
    if (input is bool) return ValidationResult.ok(input);
    return ValidationResult.failure(['Expected "$key" to be a boolean.']);
  }

  @override
  bool deserialize(SerdeCtx serdeCtx, bool serialized) {
    return serialized;
  }

  @override
  Iterable<Object?> get props => [];
}

class _GraphQLNumType<T extends num> extends GraphQLScalarType<T, T> {
  @override
  final String name;
  @override
  final String description;
  final String expected;

  _GraphQLNumType(this.name, this.description, this.expected);

  @override
  ValidationResult<T> validate(String key, Object? input) {
    if (input is T) return ValidationResult.ok(input);

    return ValidationResult.failure(['Expected "$key" to be $expected.']);
  }

  @override
  T deserialize(SerdeCtx serdeCtx, T serialized) {
    return serialized;
  }

  @override
  T serialize(T value) {
    return value;
  }

  @override
  Iterable<Object?> get props => [name];
}

class _GraphQLStringType extends GraphQLScalarType<String, String> {
  @override
  final String name;

  _GraphQLStringType._([this.name = 'String']);

  @override
  String get description => 'A character sequence.';

  @override
  String serialize(String value) => value;

  @override
  String deserialize(SerdeCtx serdeCtx, String serialized) => serialized;

  @override
  ValidationResult<String> validate(String key, Object? input) =>
      input is String
          ? ValidationResult.ok(input)
          : ValidationResult.failure(['Expected "$key" to be a string.']);

  @override
  Iterable<Object?> get props => [name];
}

class _GraphQLDateType extends GraphQLScalarType<DateTime, String>
    with _NonNullableMixin<DateTime, String> {
  _GraphQLDateType._();

  @override
  String get name => 'Date';

  @override
  String get description => 'An ISO-8601 Date.';

  @override
  String serialize(DateTime value) => value.toIso8601String();

  @override
  DateTime deserialize(SerdeCtx serdeCtx, String serialized) =>
      DateTime.parse(serialized);

  @override
  ValidationResult<String> validate(String key, Object? input) {
    return validateDateString(key, input);
  }

  @override
  Iterable<Object?> get props => [];
}

ValidationResult<String> validateDateString(String key, Object? input) {
  if (input is! String)
    return ValidationResult<String>.failure(
        ['$key must be an ISO 8601-formatted date string.']);

  try {
    DateTime.parse(input);
    return ValidationResult.ok(input);
  } on FormatException {
    return ValidationResult.failure(
        ['$key must be an ISO 8601-formatted date string.']);
  }
}

class _GraphQLTimestampType extends GraphQLScalarType<DateTime, int>
    with _NonNullableMixin<DateTime, int> {
  _GraphQLTimestampType._();

  @override
  String get name => 'Timestamp';

  @override
  String get description => 'An UNIX timestamp.';

  @override
  int serialize(DateTime value) => value.millisecondsSinceEpoch;

  @override
  DateTime deserialize(SerdeCtx serdeCtx, int serialized) =>
      DateTime.fromMillisecondsSinceEpoch(serialized);

  @override
  ValidationResult<int> validate(String key, Object? input) {
    Object? value = input;
    if (value is String) {
      value = int.tryParse(value);
    }
    final err =
        ValidationResult<int>.failure(['$key must be an UNIX timestamp.']);
    if (value is! int) {
      return err;
    }
    try {
      DateTime.fromMillisecondsSinceEpoch(value);
      return ValidationResult.ok(value);
    } catch (_) {
      return err;
    }
  }

  @override
  Iterable<Object?> get props => [];
}

class _GraphQLIdentityType<T extends Object> extends GraphQLScalarType<T, T>
    with _NonNullableMixin<T, T> {
  _GraphQLIdentityType(
    this.name,
    this.description,
    this._validate,
  );

  @override
  final String name;

  @override
  final String description;

  final ValidationResult<T> Function(String key, Object? input) _validate;

  @override
  T serialize(T value) => value;

  @override
  T deserialize(SerdeCtx serdeCtx, T serialized) => serialized;

  @override
  ValidationResult<T> validate(String key, Object? input) {
    return _validate(key, input);
  }

  @override
  Iterable<Object?> get props => [name, description, _validate];
}
