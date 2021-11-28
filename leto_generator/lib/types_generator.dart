import 'dart:async';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:leto_generator/config.dart';
import 'package:leto_generator/generator_models.dart';
import 'package:leto_generator/utils.dart';
import 'package:leto_schema/leto_schema.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

/// Generates GraphQL schemas, statically.
Builder graphQLBuilder(BuilderOptions options) {
  return SharedPartBuilder(
    [_GraphQLGenerator(Config.fromJson(options.config))],
    'graphql_types',
  );
}

class _GraphQLGenerator extends GeneratorForAnnotation<GraphQLObjectDec> {
  final Config config;

  _GraphQLGenerator(this.config);

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is ClassElement) {
      try {
        final ctx = GeneratorCtx(buildStep: buildStep, config: config);
        final lib = await buildSchemaLibrary(element, ctx, annotation);
        return lib.accept(DartEmitter()).toString();
      } catch (e, s) {
        print('$e $s');
        return '/*$e $s*/';
      }
    } else {
      throw UnsupportedError('@GraphQLClass() is only supported on classes.');
    }
  }

  Future<Library> buildSchemaLibrary(
    ClassElement clazz,
    GeneratorCtx ctx,
    ConstantReader ann,
  ) async {
    final hasFrezzed = freezedTypeChecker.hasAnnotationOfExact(clazz);
    final hasJsonAnnotation =
        jsonSerializableTypeChecker.hasAnnotationOf(clazz);
    final enumAnnotation = const TypeChecker.fromRuntime(GraphQLEnum)
        .firstAnnotationOfExact(clazz);
    final unionAnnotation = const TypeChecker.fromRuntime(GraphQLUnion)
        .firstAnnotationOfExact(clazz);

    if (clazz.isEnum && enumAnnotation == null) {
      throw Exception(
        'Please use `@GraphQLEnum()` for enum elements. Class: ${clazz.name}.',
      );
    }

    if (hasFrezzed || unionAnnotation != null) {
      return generateFromConstructors(clazz, ctx);
    } else if (enumAnnotation != null) {
      return generateEnum(clazz, ctx, enumAnnotation);
    } else {
      final className = clazz.name;
      final redirectedName =
          clazz.constructors.firstWhere(isFreezedVariantConstructor).name;
      final classInfo = UnionVarianInfo(
        isInterface: isInterface(clazz),
        typeParams: clazz.typeParameters,
        hasFrezzed: false,
        isUnion: false,
        inputConfig: inputTypeAnnotation(clazz),
        hasFromJson: hasFromJson(clazz),
        classConfig: getClassConfig(ctx, clazz),
        interfaces: getGraphQLInterfaces(ctx, clazz),
        typeName: className,
        constructorName: redirectedName.isEmpty ? className : redirectedName,
        unionName: className,
        description: getDescription(clazz, clazz.documentationComment),
        deprecationReason: getDeprecationReason(clazz),
        fields: await Future.wait(
          fieldsFromClass(clazz, ctx),
        ),
        attachments: getAttachments(clazz),
      );
      return Library((l) {
        // l.directives.addAll(
        //   ctx.config.customTypes.map((e) => Directive.import(e.import)),
        // );

        l.body.add(classInfo.serializer());
        l.body.add(Code(classInfo.typeDefinitionCode()));
      });
    }
  }
}

Future<Library> generateFromConstructors(
  ClassElement clazz,
  GeneratorCtx ctx,
) async {
  final hasFrezzed = freezedTypeChecker.hasAnnotationOfExact(clazz);
  final _annot =
      const TypeChecker.fromRuntime(GraphQLUnion).firstAnnotationOfExact(clazz);

  final annot = _annot == null
      ? null
      : GraphQLUnion(
          name: _annot.getField('name')?.toStringValue(),
          unnestIfEqual: _annot.getField('unnestIfEqual')?.toBoolValue(),
        );
  final variants = await freezedVariants(clazz, ctx);

  return Library((l) {
    // l.directives.addAll(
    //   ctx.config.customTypes.map((e) => Directive.import(e.import)),
    // );

    if (hasFrezzed) {
      /// We need to generate each Object variant for freezed annotated classes
      for (final variant in variants) {
        l.body.add(variant.serializer());
        l.body.add(Code(variant.typeDefinitionCode()));
      }
    }
    if (variants.length == 1 && annot == null) {
      /// if it's a single freezed constructor, don't generate the union
      return;
    }

    final className = clazz.name;
    final fieldName = '${ReCase(className).camelCase}$graphqlTypeSuffix';
    final description = getDescription(clazz, clazz.documentationComment);
    final attachments = getAttachments(clazz);

    l.body.add(Code('''
${hasFromJson(clazz) ? serializerDefinitionCode(className, hasFrezzed: false) : ''}

GraphQLUnionType<$className>? _$fieldName;

/// Generated from [$className]
GraphQLUnionType<$className> get $fieldName {
  if (_$fieldName != null) return _$fieldName!;
  _$fieldName = GraphQLUnionType(
    '${annot?.name ?? className}',
    const [],
    ${description == null ? '' : 'description: "$description",'}
    ${attachments == null ? '' : 'extra: GraphQLTypeDefinitionExtra.attach($attachments),'}
  );
  _$fieldName!.possibleTypes.addAll([
      ${variants.map((e) => e.fieldName).join(',')},
  ]);
  return _$fieldName!;
}
'''));

    // Map<String, Object?> _\$${typeName}ToJson($typeName instance) => instance.toJson();

    // GraphQLObjectField<String, String, P>
    // $fieldName$unionKeySuffix<P extends $typeName>()
    //    => field(
    //   'runtimeType',
    //   enumTypeFromStrings('${typeName}Type', [
    //     ${variants.map((e) => '"${e.constructorName}"').join(',')}
    //   ]),
    // );
  });
}

Library generateEnum(
  ClassElement clazz,
  GeneratorCtx ctx,
  DartObject enumAnnotation,
) {
  final index =
      enumAnnotation.getField('valuesCase')?.getField('index')?.toIntValue() ??
          ctx.config.enumValuesCase?.index;
  final valuesCase = index == null ? null : EnumNameCase.values[index];
  final annot = GraphQLEnum(
    valuesCase: valuesCase,
    name: enumAnnotation.getField('name')?.toStringValue(),
  );

  String _mapVariantName(String name) {
    if (valuesCase == null) return name;
    final _recase = ReCase(name);
    switch (valuesCase) {
      case EnumNameCase.CONSTANT_CASE:
        return _recase.constantCase;
      case EnumNameCase.PascalCase:
        return _recase.pascalCase;
      case EnumNameCase.Pascal_Underscore_Case:
        return _recase.titleCase.replaceAll(' ', '_');
      case EnumNameCase.camelCase:
        return _recase.camelCase;
      case EnumNameCase.snake_case:
        return _recase.snakeCase;
      case EnumNameCase.none:
        return name;
    }
  }

  final allNames = <String>{};

  const _variantChecker = TypeChecker.fromRuntime(GraphQLEnumVariant);
  final variants = List.of(
    clazz.fields
        .where(
            (f) => f.isEnumConstant || _variantChecker.hasAnnotationOfExact(f))
        .map(
      (variant) {
        final String name;
        if (!variant.isEnumConstant) {
          if (!variant.isStatic) {
            throw Exception(
              'A $GraphQLEnumVariant should be a static field.'
              ' In ${clazz.name}.${variant.name}.',
            );
          } else if (variant.type.element != clazz) {
            throw Exception(
              'All $GraphQLEnumVariant should be a instances'
              ' of the $GraphQLEnum annotated class.'
              ' In ${clazz.name}.${variant.name}.',
            );
          }

          name = _variantChecker
                  .firstAnnotationOfExact(variant)!
                  .getField('name')!
                  .toStringValue() ??
              _mapVariantName(variant.name);
        } else {
          name = _mapVariantName(variant.name);
        }
        allNames.add(name);

        final description =
            getDescription(variant, variant.documentationComment);
        final deprecationReason = getDeprecationReason(variant);
        final attachments = getAttachments(variant);

        return refer('GraphQLEnumValue').call([
          literalString(name),
          refer('${clazz.name}.${variant.name}'),
        ], {
          if (description != null && description.isNotEmpty)
            'description': literalString(description),
          if (deprecationReason != null)
            'deprecationReason': literalString(deprecationReason),
          if (attachments != null) 'attachments': refer(attachments),
        });
      },
    ),
  );
  if (variants.isEmpty) {
    throw Exception(
      'Enum "${clazz.name}" should have at least one'
      ' $GraphQLEnumVariant annotated static field.',
    );
  } else if (allNames.length != variants.length) {
    throw Exception(
      'All enum variant names should be unique: $allNames. In ${clazz.name}.',
    );
  } else if (const ['true', 'false', 'null'].any(allNames.contains)) {
    throw Exception(
      "Can't have any of 'true', 'false' or 'null' as names"
      ' of variants in enums: $allNames. In ${clazz.name}.',
    );
  }
  return Library((b) {
    b.body.add(Field((b) {
      final args = <Expression>[
        literalString(annot.name ?? clazz.name),
        literalList(variants),
      ];
      final description = getDescription(clazz, clazz.documentationComment);
      final attachments = getAttachments(clazz);
      b
        ..name = '${ReCase(clazz.name).camelCase}$graphqlTypeSuffix'
        ..docs.add('/// Auto-generated from [${clazz.name}].')
        ..type = TypeReference((b) => b
          ..symbol = 'GraphQLEnumType'
          ..types.add(refer(clazz.name)))
        ..modifier = FieldModifier.final$
        ..assignment = refer('GraphQLEnumType').call(
          args,
          {
            if (description != null) 'description': literalString(description),
            if (attachments != null)
              'extra': refer('GraphQLTypeDefinitionExtra.attach').call([
                refer(attachments),
              ])
          },
        ).code;
    }));
  });
}
