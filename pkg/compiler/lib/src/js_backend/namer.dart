// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of js_backend;

/**
 * Assigns JavaScript identifiers to Dart variables, class-names and members.
 *
 * Names are generated through three stages:
 *
 * 1. Original names and proposed names
 * 2. Disambiguated names (also known as "mangled names")
 * 3. Annotated names
 *
 * Original names are names taken directly from the input.
 *
 * Proposed names are either original names or synthesized names for input
 * elements that do not have original names.
 *
 * Disambiguated names are derived from the above, but are mangled to ensure
 * uniqueness within some namespace (e.g. as fields on the same JS object).
 * In [MinifyNamer], disambiguated names are also minified.
 *
 * Annotated names are names generated from a disambiguated name. Annnotated
 * names must be computable at runtime by prefixing/suffixing constant strings
 * onto the disambiguated name.
 *
 * For example, some entity called `x` might be associated with these names:
 *
 *     Original name: `x`
 *
 *     Disambiguated name: `x1` (if something else was called `x`)
 *
 *     Annotated names: `x1`     (field name)
 *                      `get$x1` (getter name)
 *                      `set$x1` (setter name)
 *
 * The [Namer] can choose the disambiguated names, and to some degree the
 * prefix/suffix constants used to construct annotated names. It cannot choose
 * annotated names with total freedom, for example, it cannot choose that the
 * getter for `x1` should be called `getX` -- the annotated names are always
 * built by concatenation.
 *
 * Disambiguated names must be chosen such that none of the annotated names can
 * clash with each other. This may happen even if the disambiguated names are
 * distinct, for example, suppose a field `x` and `get$x` exists in the input:
 *
 *     Original names: `x` and `get$x`
 *
 *     Disambiguated names: `x` and `get$x` (the two names a different)
 *
 *     Annotated names: `x` (field for `x`)
 *                      `get$x` (getter for `x`)
 *                      `get$x` (field for `get$x`)
 *                      `get$get$x` (getter for `get$x`)
 *
 * The getter for `x` clashes with the field name for `get$x`, so the
 * disambiguated names are invalid.
 *
 * Additionally, disambiguated names must be chosen such that all annotated
 * names are valid JavaScript identifiers and do not coincide with a native
 * JavaScript property such as `__proto__`.
 *
 * The following annotated names are generated for instance members, where
 * <NAME> denotes the disambiguated name.
 *
 * 0. The disambiguated name can itself be seen as an annotated name.
 *
 * 1. Multiple annotated names exist for the `call` method, encoding arity and
 *    named parameters with the pattern:
 *
 *       call$<N>$namedParam1...$namedParam<M>
 *
 *    where <N> is the number of parameters (required and optional) and <M> is
 *    the number of named parameters, and namedParam<n> are the names of the
 *    named parameters in alphabetical order.
 *
 *    Note that the same convention is used for the *proposed name* of other
 *    methods. Thus, for ordinary methods, the suffix becomes embedded in the
 *    disambiguated name (and can be minified), whereas for the 'call' method,
 *    the suffix is an annotation that must be computable at runtime
 *    (and thus cannot be minified).
 *
 *    Note that the ordering of named parameters is not encapsulated in the
 *    [Namer], and is hardcoded into other components, such as [Element] and
 *    [Selector].
 *
 * 2. The getter/setter for a field:
 *
 *        get$<NAME>
 *        set$<NAME>
 *
 *    (The [getterPrefix] and [setterPrefix] are different in [MinifyNamer]).
 *
 * 3. The `is` and operator uses the following names:
 *
 *        $is<NAME>
 *        $as<NAME>
 *
 * For local variables, the [Namer] only provides *proposed names*. These names
 * must be disambiguated elsewhere.
 */
class Namer {

  static const List<String> javaScriptKeywords = const <String>[
    // These are current keywords.
    "break", "delete", "function", "return", "typeof", "case", "do", "if",
    "switch", "var", "catch", "else", "in", "this", "void", "continue",
    "false", "instanceof", "throw", "while", "debugger", "finally", "new",
    "true", "with", "default", "for", "null", "try",

    // These are future keywords.
    "abstract", "double", "goto", "native", "static", "boolean", "enum",
    "implements", "package", "super", "byte", "export", "import", "private",
    "synchronized", "char", "extends", "int", "protected", "throws",
    "class", "final", "interface", "public", "transient", "const", "float",
    "long", "short", "volatile"
  ];

  static const List<String> reservedPropertySymbols =
      const <String>[
        "__proto__", "prototype", "constructor", "call",
        // "use strict" disallows the use of "arguments" and "eval" as
        // variable names or property names. See ECMA-262, Edition 5.1,
        // section 11.1.5 (for the property names).
        "eval", "arguments"];

  // Symbols that we might be using in our JS snippets.
  static const List<String> reservedGlobalSymbols = const <String>[
    // Section references are from Ecma-262
    // (http://www.ecma-international.org/publications/files/ECMA-ST/Ecma-262.pdf)

    // 15.1.1 Value Properties of the Global Object
    "NaN", "Infinity", "undefined",

    // 15.1.2 Function Properties of the Global Object
    "eval", "parseInt", "parseFloat", "isNaN", "isFinite",

    // 15.1.3 URI Handling Function Properties
    "decodeURI", "decodeURIComponent",
    "encodeURI",
    "encodeURIComponent",

    // 15.1.4 Constructor Properties of the Global Object
    "Object", "Function", "Array", "String", "Boolean", "Number", "Date",
    "RegExp", "Error", "EvalError", "RangeError", "ReferenceError",
    "SyntaxError", "TypeError", "URIError",

    // 15.1.5 Other Properties of the Global Object
    "Math",

    // 10.1.6 Activation Object
    "arguments",

    // B.2 Additional Properties (non-normative)
    "escape", "unescape",

    // Window props (https://developer.mozilla.org/en/DOM/window)
    "applicationCache", "closed", "Components", "content", "controllers",
    "crypto", "defaultStatus", "dialogArguments", "directories",
    "document", "frameElement", "frames", "fullScreen", "globalStorage",
    "history", "innerHeight", "innerWidth", "length",
    "location", "locationbar", "localStorage", "menubar",
    "mozInnerScreenX", "mozInnerScreenY", "mozScreenPixelsPerCssPixel",
    "name", "navigator", "opener", "outerHeight", "outerWidth",
    "pageXOffset", "pageYOffset", "parent", "personalbar", "pkcs11",
    "returnValue", "screen", "scrollbars", "scrollMaxX", "scrollMaxY",
    "self", "sessionStorage", "sidebar", "status", "statusbar", "toolbar",
    "top", "window",

    // Window methods (https://developer.mozilla.org/en/DOM/window)
    "alert", "addEventListener", "atob", "back", "blur", "btoa",
    "captureEvents", "clearInterval", "clearTimeout", "close", "confirm",
    "disableExternalCapture", "dispatchEvent", "dump",
    "enableExternalCapture", "escape", "find", "focus", "forward",
    "GeckoActiveXObject", "getAttention", "getAttentionWithCycleCount",
    "getComputedStyle", "getSelection", "home", "maximize", "minimize",
    "moveBy", "moveTo", "open", "openDialog", "postMessage", "print",
    "prompt", "QueryInterface", "releaseEvents", "removeEventListener",
    "resizeBy", "resizeTo", "restore", "routeEvent", "scroll", "scrollBy",
    "scrollByLines", "scrollByPages", "scrollTo", "setInterval",
    "setResizeable", "setTimeout", "showModalDialog", "sizeToContent",
    "stop", "uuescape", "updateCommands", "XPCNativeWrapper",
    "XPCSafeJSOjbectWrapper",

    // Mozilla Window event handlers, same cite
    "onabort", "onbeforeunload", "onchange", "onclick", "onclose",
    "oncontextmenu", "ondragdrop", "onerror", "onfocus", "onhashchange",
    "onkeydown", "onkeypress", "onkeyup", "onload", "onmousedown",
    "onmousemove", "onmouseout", "onmouseover", "onmouseup",
    "onmozorientation", "onpaint", "onreset", "onresize", "onscroll",
    "onselect", "onsubmit", "onunload",

    // Safari Web Content Guide
    // http://developer.apple.com/library/safari/#documentation/AppleApplications/Reference/SafariWebContent/SafariWebContent.pdf
    // WebKit Window member data, from WebKit DOM Reference
    // (http://developer.apple.com/safari/library/documentation/AppleApplications/Reference/WebKitDOMRef/DOMWindow_idl/Classes/DOMWindow/index.html)
    "ontouchcancel", "ontouchend", "ontouchmove", "ontouchstart",
    "ongesturestart", "ongesturechange", "ongestureend",

    // extra window methods
    "uneval",

    // keywords https://developer.mozilla.org/en/New_in_JavaScript_1.7,
    // https://developer.mozilla.org/en/New_in_JavaScript_1.8.1
    "getPrototypeOf", "let", "yield",

    // "future reserved words"
    "abstract", "int", "short", "boolean", "interface", "static", "byte",
    "long", "char", "final", "native", "synchronized", "float", "package",
    "throws", "goto", "private", "transient", "implements", "protected",
    "volatile", "double", "public",

    // IE methods
    // (http://msdn.microsoft.com/en-us/library/ms535873(VS.85).aspx#)
    "attachEvent", "clientInformation", "clipboardData", "createPopup",
    "dialogHeight", "dialogLeft", "dialogTop", "dialogWidth",
    "onafterprint", "onbeforedeactivate", "onbeforeprint",
    "oncontrolselect", "ondeactivate", "onhelp", "onresizeend",

    // Common browser-defined identifiers not defined in ECMAScript
    "event", "external", "Debug", "Enumerator", "Global", "Image",
    "ActiveXObject", "VBArray", "Components",

    // Functions commonly defined on Object
    "toString", "getClass", "constructor", "prototype", "valueOf",

    // Client-side JavaScript identifiers
    "Anchor", "Applet", "Attr", "Canvas", "CanvasGradient",
    "CanvasPattern", "CanvasRenderingContext2D", "CDATASection",
    "CharacterData", "Comment", "CSS2Properties", "CSSRule",
    "CSSStyleSheet", "Document", "DocumentFragment", "DocumentType",
    "DOMException", "DOMImplementation", "DOMParser", "Element", "Event",
    "ExternalInterface", "FlashPlayer", "Form", "Frame", "History",
    "HTMLCollection", "HTMLDocument", "HTMLElement", "IFrame", "Image",
    "Input", "JSObject", "KeyEvent", "Link", "Location", "MimeType",
    "MouseEvent", "Navigator", "Node", "NodeList", "Option", "Plugin",
    "ProcessingInstruction", "Range", "RangeException", "Screen", "Select",
    "Table", "TableCell", "TableRow", "TableSelection", "Text", "TextArea",
    "UIEvent", "Window", "XMLHttpRequest", "XMLSerializer",
    "XPathException", "XPathResult", "XSLTProcessor",

    // These keywords trigger the loading of the java-plugin. For the
    // next-generation plugin, this results in starting a new Java process.
    "java", "Packages", "netscape", "sun", "JavaObject", "JavaClass",
    "JavaArray", "JavaMember",

    // ES6 collections.
    "Map",
  ];

  static const List<String> reservedGlobalObjectNames = const <String>[
      "A",
      "B",
      "C", // Global object for *C*onstants.
      "D",
      "E",
      "F",
      "G",
      "H", // Global object for internal (*H*elper) libraries.
      // I is used for used for the Isolate function.
      "J", // Global object for the interceptor library.
      "K",
      "L",
      "M",
      "N",
      "O",
      "P", // Global object for other *P*latform libraries.
      "Q",
      "R",
      "S",
      "T",
      "U",
      "V",
      "W", // Global object for *W*eb libraries (dart:html).
      "X",
      "Y",
      "Z",
  ];

  static const List<String> reservedGlobalHelperFunctions = const <String>[
      "init",
      "Isolate",
  ];

  static final List<String> userGlobalObjects =
      new List.from(reservedGlobalObjectNames)
      ..remove('C')
      ..remove('H')
      ..remove('J')
      ..remove('P')
      ..remove('W');

  Set<String> _jsReserved = null;
  /// Names that cannot be used by members, top level and static
  /// methods.
  Set<String> get jsReserved {
    if (_jsReserved == null) {
      _jsReserved = new Set<String>();
      _jsReserved.addAll(javaScriptKeywords);
      _jsReserved.addAll(reservedPropertySymbols);
    }
    return _jsReserved;
  }

  Set<String> _jsVariableReserved = null;
  /// Names that cannot be used by local variables and parameters.
  Set<String> get jsVariableReserved {
    if (_jsVariableReserved == null) {
      _jsVariableReserved = new Set<String>();
      _jsVariableReserved.addAll(javaScriptKeywords);
      _jsVariableReserved.addAll(reservedPropertySymbols);
      _jsVariableReserved.addAll(reservedGlobalSymbols);
      _jsVariableReserved.addAll(reservedGlobalObjectNames);
      // 26 letters in the alphabet, 25 not counting I.
      assert(reservedGlobalObjectNames.length == 25);
      _jsVariableReserved.addAll(reservedGlobalHelperFunctions);
    }
    return _jsVariableReserved;
  }

  final String asyncPrefix = r"$async$";
  final String staticStateHolder = r'$';
  final String getterPrefix = r'get$';
  final String lazyGetterPrefix = r'$get$';
  final String setterPrefix = r'set$';
  final String superPrefix = r'super$';
  final String metadataField = '@';
  final String callPrefix = 'call';
  final String callCatchAllName = r'call*';
  final String callNameField = r'$callName';
  final String reflectableField = r'$reflectable';
  final String reflectionInfoField = r'$reflectionInfo';
  final String reflectionNameField = r'$reflectionName';
  final String metadataIndexField = r'$metadataIndex';
  final String defaultValuesField = r'$defaultValues';
  final String methodsWithOptionalArgumentsField =
      r'$methodsWithOptionalArguments';
  final String deferredAction = r'$deferredAction';

  final String classDescriptorProperty = r'^';
  final String requiredParameterField = r'$requiredArgCount';

  /// The non-minifying namer's [callPrefix] with a dollar after it.
  static const String _callPrefixDollar = r'call$';

  static final jsAst.Name _literalSuper = new StringBackedName("super");
  static final jsAst.Name _literalDollar = new StringBackedName(r'$');
  static final jsAst.Name _literalUnderscore = new StringBackedName('_');
  static final jsAst.Name literalPlus = new StringBackedName('+');
  static final jsAst.Name _literalDynamic = new StringBackedName("dynamic");

  jsAst.Name _literalAsyncPrefix;
  jsAst.Name _literalGetterPrefix;
  jsAst.Name _literalSetterPrefix;
  jsAst.Name _literalLazyGetterPrefix;

  // Name of property in a class description for the native dispatch metadata.
  final String nativeSpecProperty = '%';

  static final RegExp IDENTIFIER = new RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
  static final RegExp NON_IDENTIFIER_CHAR = new RegExp(r'[^A-Za-z_0-9$]');

  final Compiler compiler;

  /// Used disambiguated names in the global namespace, issued by
  /// [_disambiguateGlobal], and [_disambiguateInternalGlobal].
  ///
  /// Although global names are distributed across a number of global objects,
  /// (see [globalObjectFor]), we currently use a single namespace for all these
  /// names.
  final Set<String> usedGlobalNames = new Set<String>();
  final Map<Element, jsAst.Name> userGlobals =
      new HashMap<Element, jsAst.Name>();
  final Map<String, jsAst.Name> internalGlobals =
      new HashMap<String, jsAst.Name>();

  /// Used disambiguated names in the instance namespace, issued by
  /// [_disambiguateMember], [_disambiguateInternalMember],
  /// [_disambiguateOperator], and [reservePublicMemberName].
  final Set<String> usedInstanceNames = new Set<String>();
  final Map<String, jsAst.Name> userInstanceMembers =
      new HashMap<String, jsAst.Name>();
  final Map<Element, jsAst.Name> internalInstanceMembers =
      new HashMap<Element, jsAst.Name>();
  final Map<String, jsAst.Name> userInstanceOperators =
      new HashMap<String, jsAst.Name>();

  /// Used to disambiguate names for constants in [constantName].
  final Set<String> usedConstantNames = new Set<String>();

  Set<String> getUsedNames(NamingScope scope) {
    if (scope == NamingScope.global) {
      return usedGlobalNames;
    } else if (scope == NamingScope.instance){
      return usedInstanceNames;
    } else {
      assert(scope == NamingScope.constant);
      return usedConstantNames;
    }
  }

  final Map<String, int> popularNameCounters = <String, int>{};

  final Map<LibraryElement, String> libraryLongNames =
      new HashMap<LibraryElement, String>();

  final Map<ConstantValue, jsAst.Name> constantNames =
      new HashMap<ConstantValue, jsAst.Name>();
  final Map<ConstantValue, String> constantLongNames =
      <ConstantValue, String>{};
  ConstantCanonicalHasher constantHasher;

  /// Maps private names to a library that may use that name without prefixing
  /// itself. Used for building proposed names.
  final Map<String, LibraryElement> shortPrivateNameOwners =
      <String, LibraryElement>{};

  /// Maps proposed names to *suggested* disambiguated names.
  ///
  /// Suggested names are hints to the [MinifyNamer], suggesting that a specific
  /// names be given to the first item with the given proposed name.
  ///
  /// This is currently used in [MinifyNamer] to assign very short minified
  /// names to things that tend to be used very often.
  final Map<String, String> suggestedGlobalNames = <String, String>{};
  final Map<String, String> suggestedInstanceNames = <String, String>{};

  Map<String, String> getSuggestedNames(NamingScope scope) {
    if (scope == NamingScope.global) {
      return suggestedGlobalNames;
    } else if (scope == NamingScope.instance) {
      return suggestedInstanceNames;
    } else {
      assert(scope == NamingScope.constant);
      return const {};
    }
  }


  /// Used to store unique keys for library names. Keys are not used as names,
  /// nor are they visible in the output. The only serve as an internal
  /// key into maps.
  final Map<LibraryElement, String> _libraryKeys =
      new HashMap<LibraryElement, String>();

  Namer(Compiler compiler)
      : compiler = compiler,
        constantHasher = new ConstantCanonicalHasher(compiler),
        functionTypeNamer = new FunctionTypeNamer(compiler) {
    _literalAsyncPrefix = new StringBackedName(asyncPrefix);
    _literalGetterPrefix = new StringBackedName(getterPrefix);
    _literalSetterPrefix = new StringBackedName(setterPrefix);
    _literalLazyGetterPrefix = new StringBackedName(lazyGetterPrefix);
  }

  JavaScriptBackend get backend => compiler.backend;

  String get deferredTypesName => 'deferredTypes';
  String get isolateName => 'Isolate';
  String get isolatePropertiesName => r'$isolateProperties';
  jsAst.Name get noSuchMethodName => publicInstanceMethodNameByArity(
      Compiler.NO_SUCH_METHOD, Compiler.NO_SUCH_METHOD_ARG_COUNT);
  /**
   * Some closures must contain their name. The name is stored in
   * [STATIC_CLOSURE_NAME_NAME].
   */
  String get STATIC_CLOSURE_NAME_NAME => r'$name';
  String get closureInvocationSelectorName => Compiler.CALL_OPERATOR_NAME;
  bool get shouldMinify => false;

  /// Returns the string that is to be used as the result of a call to
  /// [JS_GET_NAME] at [node] with argument [name].
  jsAst.Name getNameForJsGetName(Node node, JsGetName name) {
    switch (name) {
      case JsGetName.GETTER_PREFIX: return asName(getterPrefix);
      case JsGetName.SETTER_PREFIX: return asName(setterPrefix);
      case JsGetName.CALL_PREFIX: return asName(callPrefix);
      case JsGetName.CALL_PREFIX0: return asName('${callPrefix}\$0');
      case JsGetName.CALL_PREFIX1: return asName('${callPrefix}\$1');
      case JsGetName.CALL_PREFIX2: return asName('${callPrefix}\$2');
      case JsGetName.CALL_PREFIX3: return asName('${callPrefix}\$3');
      case JsGetName.CALL_CATCH_ALL: return asName(callCatchAllName);
      case JsGetName.REFLECTABLE: return asName(reflectableField);
      case JsGetName.CLASS_DESCRIPTOR_PROPERTY:
        return asName(classDescriptorProperty);
      case JsGetName.REQUIRED_PARAMETER_PROPERTY:
        return asName(requiredParameterField);
      case JsGetName.DEFAULT_VALUES_PROPERTY: return asName(defaultValuesField);
      case JsGetName.CALL_NAME_PROPERTY: return asName(callNameField);
      case JsGetName.DEFERRED_ACTION_PROPERTY: return asName(deferredAction);
      case JsGetName.OPERATOR_AS_PREFIX: return asName(operatorAsPrefix);
      case JsGetName.SIGNATURE_NAME: return asName(operatorSignature);
      case JsGetName.TYPEDEF_TAG: return asName(typedefTag);
      case JsGetName.FUNCTION_TYPE_VOID_RETURN_TAG:
        return asName(functionTypeVoidReturnTag);
      case JsGetName.FUNCTION_TYPE_RETURN_TYPE_TAG:
        return asName(functionTypeReturnTypeTag);
      case JsGetName.FUNCTION_TYPE_REQUIRED_PARAMETERS_TAG:
        return asName(functionTypeRequiredParametersTag);
      case JsGetName.FUNCTION_TYPE_OPTIONAL_PARAMETERS_TAG:
        return asName(functionTypeOptionalParametersTag);
      case JsGetName.FUNCTION_TYPE_NAMED_PARAMETERS_TAG:
        return asName(functionTypeNamedParametersTag);
      case JsGetName.IS_INDEXABLE_FIELD_NAME:
        Element cls = backend.findHelper('JavaScriptIndexingBehavior');
        return operatorIs(cls);
      case JsGetName.NULL_CLASS_TYPE_NAME:
        return runtimeTypeName(compiler.nullClass);
      case JsGetName.OBJECT_CLASS_TYPE_NAME:
        return runtimeTypeName(compiler.objectClass);
      case JsGetName.FUNCTION_CLASS_TYPE_NAME:
        return runtimeTypeName(compiler.functionClass);
      default:
        compiler.reportError(
          node, MessageKind.GENERIC,
          {'text': 'Error: Namer has no name for "$name".'});
        return asName('BROKEN');
    }
  }

  /// Disambiguated name for [constant].
  ///
  /// Unique within the global-member namespace.
  jsAst.Name constantName(ConstantValue constant) {
    // In the current implementation it doesn't make sense to give names to
    // function constants since the function-implementation itself serves as
    // constant and can be accessed directly.
    assert(!constant.isFunction);
    jsAst.Name result = constantNames[constant];
    if (result == null) {
      String longName = constantLongName(constant);
      result = getFreshName(NamingScope.constant, longName);
      constantNames[constant] = result;
    }
    return result;
  }

  /// Proposed name for [constant].
  String constantLongName(ConstantValue constant) {
    String longName = constantLongNames[constant];
    if (longName == null) {
      longName = new ConstantNamingVisitor(compiler, constantHasher)
          .getName(constant);
      constantLongNames[constant] = longName;
    }
    return longName;
  }

  String breakLabelName(LabelDefinition label) {
    return '\$${label.labelName}\$${label.target.nestingLevel}';
  }

  String implicitBreakLabelName(JumpTarget target) {
    return '\$${target.nestingLevel}';
  }

  // We sometimes handle continue targets differently from break targets,
  // so we have special continue-only labels.
  String continueLabelName(LabelDefinition label) {
    return 'c\$${label.labelName}\$${label.target.nestingLevel}';
  }

  String implicitContinueLabelName(JumpTarget target) {
    return 'c\$${target.nestingLevel}';
  }

  /**
   * If the [originalName] is not private returns [originalName]. Otherwise
   * mangles the [originalName] so that each library has its own distinguished
   * version of the name.
   *
   * Although the name is not guaranteed to be unique within any namespace,
   * clashes are very unlikely in practice. Therefore, it can be used in cases
   * where uniqueness is nice but not a strict requirement.
   *
   * The resulting name is a *proposed name* and is never minified.
   */
  String privateName(Name originalName) {
    String text = originalName.text;

    // Public names are easy.
    if (!originalName.isPrivate) return text;

    LibraryElement library = originalName.library;

    // The first library asking for a short private name wins.
    LibraryElement owner =
        shortPrivateNameOwners.putIfAbsent(text, () => library);

    if (owner == library) {
      return text;
    } else {
      // Make sure to return a private name that starts with _ so it
      // cannot clash with any public names.
      // The name is still not guaranteed to be unique, since both the library
      // name and originalName could contain $ symbols and as the library
      // name itself might clash.
      String libraryName = _proposeNameForGlobal(library);
      return "_$libraryName\$$text";
    }
  }

  String _proposeNameForConstructorBody(ConstructorBodyElement method) {
    String name = Elements.reconstructConstructorNameSourceString(method);
    // We include the method suffix on constructor bodies. It has no purpose,
    // but this way it produces the same names as previous versions of the
    // Namer class did.
    List<String> suffix = callSuffixForSignature(method.functionSignature);
    return '$name\$${suffix.join(r'$')}';
  }

  /// Name for a constructor body.
  jsAst.Name constructorBodyName(FunctionElement ctor) {
    return _disambiguateInternalMember(ctor,
        () => _proposeNameForConstructorBody(ctor));
  }

  /// Annotated name for [method] encoding arity and named parameters.
  jsAst.Name instanceMethodName(FunctionElement method) {
    if (method.isGenerativeConstructorBody) {
      return constructorBodyName(method);
    }
    return invocationName(new Selector.fromElement(method));
  }

  /// Annotated name for a public method with the given [originalName]
  /// and [arity] and no named parameters.
  jsAst.Name publicInstanceMethodNameByArity(String originalName,
                                             int arity) {
    return invocationName(new Selector.call(originalName, null, arity));
  }

  /// Returns the annotated name for a variant of `call`.
  /// The result has the form:
  ///
  ///     call$<N>$namedParam1...$namedParam<M>
  ///
  /// This name cannot be minified because it is generated by string
  /// concatenation at runtime, by applyFunction in js_helper.dart.
  jsAst.Name deriveCallMethodName(List<String> suffix) {
    // TODO(asgerf): Avoid clashes when named parameters contain $ symbols.
    return new StringBackedName('$callPrefix\$${suffix.join(r'$')}');
  }

  /// The suffix list for the pattern:
  ///
  ///     $<N>$namedParam1...$namedParam<M>
  ///
  /// This is used for the annotated names of `call`, and for the proposed name
  /// for other instance methods.
  List<String> callSuffixForStructure(CallStructure callStructure) {
    List<String> suffixes = ['${callStructure.argumentCount}'];
    suffixes.addAll(callStructure.getOrderedNamedArguments());
    return suffixes;
  }

  /// The suffix list for the pattern:
  ///
  ///     $<N>$namedParam1...$namedParam<M>
  ///
  /// This is used for the annotated names of `call`, and for the proposed name
  /// for other instance methods.
  List<String> callSuffixForSignature(FunctionSignature sig) {
    List<String> suffixes = ['${sig.parameterCount}'];
    if (sig.optionalParametersAreNamed) {
      for (FormalElement param in sig.orderedOptionalParameters) {
        suffixes.add(param.name);
      }
    }
    return suffixes;
  }

  /// Annotated name for the member being invoked by [selector].
  jsAst.Name invocationName(Selector selector) {
    switch (selector.kind) {
      case SelectorKind.GETTER:
        jsAst.Name disambiguatedName =
            _disambiguateMember(selector.memberName);
        return deriveGetterName(disambiguatedName);

      case SelectorKind.SETTER:
        jsAst.Name disambiguatedName =
            _disambiguateMember(selector.memberName);
        return deriveSetterName(disambiguatedName);

      case SelectorKind.OPERATOR:
      case SelectorKind.INDEX:
        String operatorIdentifier = operatorNameToIdentifier(selector.name);
        jsAst.Name disambiguatedName =
            _disambiguateOperator(operatorIdentifier);
        return disambiguatedName; // Operators are not annotated.

      case SelectorKind.CALL:
        List<String> suffix = callSuffixForStructure(selector.callStructure);
        if (selector.name == Compiler.CALL_OPERATOR_NAME) {
          // Derive the annotated name for this variant of 'call'.
          return deriveCallMethodName(suffix);
        }
        jsAst.Name disambiguatedName =
            _disambiguateMember(selector.memberName, suffix);
        return disambiguatedName; // Methods other than call are not annotated.

      default:
        compiler.internalError(compiler.currentElement,
            'Unexpected selector kind: ${selector.kind}');
        return null;
    }
  }

  /**
   * Returns the internal name used for an invocation mirror of this selector.
   */
  jsAst.Name invocationMirrorInternalName(Selector selector)
      => invocationName(selector);

  /**
   * Returns the disambiguated name for the given field, used for constructing
   * the getter and setter names.
   */
  jsAst.Name fieldAccessorName(FieldElement element) {
    return element.isInstanceMember
        ? _disambiguateMember(element.memberName)
        : _disambiguateGlobal(element);
  }

  /**
   * Returns name of the JavaScript property used to store a static or instance
   * field.
   */
  jsAst.Name fieldPropertyName(FieldElement element) {
    return element.isInstanceMember
        ? instanceFieldPropertyName(element)
        : _disambiguateGlobal(element);
  }

  /**
   * Returns name of the JavaScript property used to store the
   * `readTypeVariable` function for the given type variable.
   */
  jsAst.Name nameForReadTypeVariable(TypeVariableElement element) {
    return _disambiguateInternalMember(element, () => element.name);
  }

  /**
   * Returns a JavaScript property name used to store [element] on one
   * of the global objects.
   *
   * Should be used together with [globalObjectFor], which denotes the object
   * on which the returned property name should be used.
   */
  jsAst.Name globalPropertyName(Element element) {
    return _disambiguateGlobal(element);
  }

  /**
   * Returns the JavaScript property name used to store an instance field.
   */
  jsAst.Name instanceFieldPropertyName(FieldElement element) {
    ClassElement enclosingClass = element.enclosingClass;

    if (element.hasFixedBackendName) {
      // Certain native fields must be given a specific name. Native names must
      // not contain '$'. We rely on this to avoid clashes.
      assert(enclosingClass.isNative &&
             !element.fixedBackendName.contains(r'$'));

      return new StringBackedName(element.fixedBackendName);
    }

    // Instances of BoxFieldElement are special. They are already created with
    // a unique and safe name. However, as boxes are not really instances of
    // classes, the usual naming scheme that tries to avoid name clashes with
    // super classes does not apply. We still do not mark the name as a
    // fixedBackendName, as we want to allow other namers to do something more
    // clever with them.
    if (element is BoxFieldElement) {
      return new StringBackedName(element.name);
    }

    // If the name of the field might clash with another field,
    // use a mangled field name to avoid potential clashes.
    // Note that if the class extends a native class, that native class might
    // have fields with fixed backend names, so we assume the worst and always
    // mangle the field names of classes extending native classes.
    // Methods on such classes are stored on the interceptor, not the instance,
    // so only fields have the potential to clash with a native property name.
    ClassWorld classWorld = compiler.world;
    if (classWorld.isUsedAsMixin(enclosingClass) ||
        _isShadowingSuperField(element) ||
        _isUserClassExtendingNative(enclosingClass)) {
      String proposeName() => '${enclosingClass.name}_${element.name}';
      return _disambiguateInternalMember(element, proposeName);
    }

    // No superclass uses the disambiguated name as a property name, so we can
    // use it for this field. This generates nicer field names since otherwise
    // the field name would have to be mangled.
    return _disambiguateMember(element.memberName);
  }

  bool _isShadowingSuperField(Element element) {
    return element.enclosingClass.hasFieldShadowedBy(element);
  }

  /// True if [class_] is a non-native class that inherits from a native class.
  bool _isUserClassExtendingNative(ClassElement class_) {
    return !class_.isNative &&
           Elements.isNativeOrExtendsNative(class_.superclass);
  }

  /// Annotated name for the setter of [element].
  jsAst.Name setterForElement(MemberElement element) {
    // We dynamically create setters from the field-name. The setter name must
    // therefore be derived from the instance field-name.
    jsAst.Name name = _disambiguateMember(element.memberName);
    return deriveSetterName(name);
  }

  /// Annotated name for the setter of any member with [disambiguatedName].
  jsAst.Name deriveSetterName(jsAst.Name disambiguatedName) {
    // We dynamically create setters from the field-name. The setter name must
    // therefore be derived from the instance field-name.
    return new SetterName(_literalSetterPrefix, disambiguatedName);
  }

  /// Annotated name for the setter of any member with [disambiguatedName].
  jsAst.Name deriveGetterName(jsAst.Name disambiguatedName) {
    // We dynamically create getters from the field-name. The getter name must
    // therefore be derived from the instance field-name.
    return new GetterName(_literalGetterPrefix, disambiguatedName);
  }

  /// Annotated name for the getter of [element].
  jsAst.Name getterForElement(MemberElement element) {
    // We dynamically create getters from the field-name. The getter name must
    // therefore be derived from the instance field-name.
    jsAst.Name name = _disambiguateMember(element.memberName);
    return deriveGetterName(name);
  }

  /// Property name for the getter of an instance member with [originalName].
  jsAst.Name getterForMember(Name originalName) {
    jsAst.Name disambiguatedName = _disambiguateMember(originalName);
    return deriveGetterName(disambiguatedName);
  }

  /// Disambiguated name for a compiler-owned global variable.
  ///
  /// The resulting name is unique within the global-member namespace.
  jsAst.Name _disambiguateInternalGlobal(String name) {
    jsAst.Name newName = internalGlobals[name];
    if (newName == null) {
      newName = getFreshName(NamingScope.global, name);
      internalGlobals[name] = newName;
    }
    return newName;
  }

  /// Returns the property name to use for a compiler-owner global variable,
  /// i.e. one that does not correspond to any element but is used as a utility
  /// global by code generation.
  ///
  /// [name] functions as both the proposed name for the global, and as a key
  /// identifying the global. The [name] must not contain `$` symbols, since
  /// the [Namer] uses those names internally.
  ///
  /// This provides an easy mechanism of avoiding a name-clash with user-space
  /// globals, although the callers of must still take care not to accidentally
  /// pass in the same [name] for two different internal globals.
  jsAst.Name internalGlobal(String name) {
    assert(!name.contains(r'$'));
    return _disambiguateInternalGlobal(name);
  }

  /// Generates a unique key for [library].
  ///
  /// Keys are meant to be used in maps and should not be visible in the output.
  String _generateLibraryKey(LibraryElement library) {
    return _libraryKeys.putIfAbsent(library, () {
      String keyBase = library.name;
      int counter = 0;
      String key = keyBase;
      while (_libraryKeys.values.contains(key)) {
        key ="$keyBase${counter++}";
      }
      return key;
    });
  }

  /// Returns the disambiguated name for a top-level or static element.
  ///
  /// The resulting name is unique within the global-member namespace.
  jsAst.Name _disambiguateGlobal(Element element) {
    // TODO(asgerf): We can reuse more short names if we disambiguate with
    // a separate namespace for each of the global holder objects.
    element = element.declaration;
    jsAst.Name newName = userGlobals[element];
    if (newName == null) {
      String proposedName = _proposeNameForGlobal(element);
      newName = getFreshName(NamingScope.global, proposedName);
      userGlobals[element] = newName;
    }
    return newName;
  }

  /// Returns the disambiguated name for an instance method or field
  /// with [originalName] in [library].
  ///
  /// [library] may be `null` if [originalName] is known to be public.
  ///
  /// This is the name used for deriving property names of accessors (getters
  /// and setters) and as property name for storing methods and method stubs.
  ///
  /// [suffixes] denote an extension of [originalName] to distiguish it from
  /// other members with that name. These are used to encode the arity and
  /// named parameters to a method. Disambiguating the same [originalName] with
  /// different [suffixes] will yield different disambiguated names.
  ///
  /// The resulting name, and its associated annotated names, are unique
  /// to the ([originalName], [suffixes]) pair within the instance-member
  /// namespace.
  jsAst.Name _disambiguateMember(Name originalName,
                                 [List<String> suffixes = const []]) {
    // Build a string encoding the library name, if the name is private.
    String libraryKey = originalName.isPrivate
            ? _generateLibraryKey(originalName.library)
            : '';

    // In the unique key, separate the name parts by '@'.
    // This avoids clashes since the original names cannot contain that symbol.
    String key = '$libraryKey@${originalName.text}@${suffixes.join('@')}';
    jsAst.Name newName = userInstanceMembers[key];
    if (newName == null) {
      String proposedName = privateName(originalName);
      if (!suffixes.isEmpty) {
        // In the proposed name, separate the name parts by '$', because the
        // proposed name must be a valid identifier, but not necessarily unique.
        proposedName += r'$' + suffixes.join(r'$');
      }
      newName = getFreshName(NamingScope.instance, proposedName,
                             sanitizeForAnnotations: true);
      userInstanceMembers[key] = newName;
    }
    return newName;
  }

  /// Returns the disambiguated name for the instance member identified by
  /// [key].
  ///
  /// When a name for an element is requested by key, it may not be requested
  /// by element at the same time, as two different names would be returned.
  ///
  /// If key has not yet been registered, [proposeName] is used to generate
  /// a name proposal for the given key.
  ///
  /// [key] must not clash with valid instance names. This is typically
  /// achieved by using at least one character in [key] that is not valid in
  /// identifiers, for example the @ symbol.
  jsAst.Name _disambiguateMemberByKey(String key, String proposeName()) {
    jsAst.Name newName = userInstanceMembers[key];
    if (newName == null) {
      String name = proposeName();
      newName = getFreshName(NamingScope.instance, name,
                             sanitizeForAnnotations: true);
      userInstanceMembers[key] = newName;
    }
    return newName;
  }

  /// Forces the public instance member with [originalName] to have the given
  /// [disambiguatedName].
  ///
  /// The [originalName] must not have been disambiguated before, and the
  /// [disambiguatedName] must not have been used.
  ///
  /// Using [_disambiguateMember] with the given [originalName] and no suffixes
  /// will subsequently return [disambiguatedName].
  void reservePublicMemberName(String originalName,
                               String disambiguatedName) {
    // Build a key that corresponds to the one built in disambiguateMember.
    String libraryPrefix = ''; // Public names have an empty library prefix.
    String suffix = ''; // We don't need any suffixes.
    String key = '$libraryPrefix@$originalName@$suffix';
    assert(!userInstanceMembers.containsKey(key));
    assert(!usedInstanceNames.contains(disambiguatedName));
    userInstanceMembers[key] = new StringBackedName(disambiguatedName);
    usedInstanceNames.add(disambiguatedName);
  }

  /// Disambiguated name unique to [element].
  ///
  /// This is used as the property name for fields, type variables,
  /// constructor bodies, and super-accessors.
  ///
  /// The resulting name is unique within the instance-member namespace.
  jsAst.Name _disambiguateInternalMember(Element element,
                                         String proposeName()) {
    jsAst.Name newName = internalInstanceMembers[element];
    if (newName == null) {
      String name = proposeName();
      bool mayClashNative = _isUserClassExtendingNative(element.enclosingClass);
      newName = getFreshName(NamingScope.instance, name,
                             sanitizeForAnnotations: true,
                             sanitizeForNatives: mayClashNative);
      internalInstanceMembers[element] = newName;
    }
    return newName;
  }

  /// Disambiguated name for the given operator.
  ///
  /// [operatorIdentifier] must be the operator's identifier, e.g.
  /// `$add` and not `+`.
  ///
  /// The resulting name is unique within the instance-member namespace.
  jsAst.Name _disambiguateOperator(String operatorIdentifier) {
    jsAst.Name newName = userInstanceOperators[operatorIdentifier];
    if (newName == null) {
      newName = getFreshName(NamingScope.instance, operatorIdentifier);
      userInstanceOperators[operatorIdentifier] = newName;
    }
    return newName;
  }

  String _generateFreshStringForName(String proposedName,
      Set<String> usedNames,
      Map<String, String> suggestedNames,
      {bool sanitizeForAnnotations: false,
       bool sanitizeForNatives: false}) {
    if (sanitizeForAnnotations) {
      proposedName = _sanitizeForAnnotations(proposedName);
    }
    if (sanitizeForNatives) {
      proposedName = _sanitizeForNatives(proposedName);
    }
    proposedName = _sanitizeForKeywords(proposedName);
    String candidate;
    if (!usedNames.contains(proposedName)) {
      candidate = proposedName;
    } else {
      int counter = popularNameCounters[proposedName];
      int i = (counter == null) ? 0 : counter;
      while (usedNames.contains("$proposedName$i")) {
        i++;
      }
      popularNameCounters[proposedName] = i + 1;
      candidate = "$proposedName$i";
    }
    usedNames.add(candidate);
    return candidate;
  }

  /// Returns an unused name.
  ///
  /// [proposedName] must be a valid JavaScript identifier.
  ///
  /// If [sanitizeForAnnotations] is `true`, then the result is guaranteed not
  /// to have the form of an annotated name.
  ///
  /// If [sanitizeForNatives] it `true`, then the result is guaranteed not to
  /// clash with a property name on a native object.
  ///
  /// Note that [MinifyNamer] overrides this method with one that produces
  /// minified names.
  jsAst.Name getFreshName(NamingScope scope,
                          String proposedName,
                          {bool sanitizeForAnnotations: false,
                           bool sanitizeForNatives: false}) {
    String candidate =
        _generateFreshStringForName(proposedName,
                                    getUsedNames(scope),
                                    getSuggestedNames(scope),
                                    sanitizeForAnnotations:
                                        sanitizeForAnnotations,
                                    sanitizeForNatives: sanitizeForNatives);
    return new StringBackedName(candidate);
  }

  /// Returns a variant of [name] that cannot clash with the annotated
  /// version of another name, that is, the resulting name can never be returned
  /// by [deriveGetterName], [deriveSetterName], [deriveCallMethodName],
  /// [operatorIs], or [substitutionName].
  ///
  /// For example, a name `get$x` would be converted to `$get$x` to ensure it
  /// cannot clash with the getter for `x`.
  ///
  /// We don't want to register all potential annotated names in
  /// [usedInstanceNames] (there are too many), so we use this step to avoid
  /// clashes between annotated and unannotated names.
  String _sanitizeForAnnotations(String name) {
    // Ensure name does not clash with a getter or setter of another name,
    // one of the other special names that start with `$`, such as `$is`,
    // or with one of the `call` stubs, such as `call$1`.
    assert(this is! MinifyNamer);
    if (name.startsWith(r'$') ||
        name.startsWith(getterPrefix) ||
        name.startsWith(setterPrefix) ||
        name.startsWith(_callPrefixDollar)) {
      name = '\$$name';
    }
    return name;
  }

  /// Returns a variant of [name] that cannot clash with a native property name
  /// (e.g. the name of a method on a JS DOM object).
  ///
  /// If [name] is not an annotated name, the result will not be an annotated
  /// name either.
  String _sanitizeForNatives(String name) {
    if (!name.contains(r'$')) {
      // Prepend $$. The result must not coincide with an annotated name.
      name = '\$\$$name';
    }
    return name;
  }

  /**
   * Returns a proposed name for the given top-level or static element.
   * The returned id is guaranteed to be a valid JS-id.
   */
  String _proposeNameForGlobal(Element element) {
    assert(!element.isInstanceMember);
    String name;
    if (element.isGenerativeConstructor) {
      name = "${element.enclosingClass.name}\$"
             "${element.name}";
    } else if (element.isFactoryConstructor) {
      // TODO(johnniwinther): Change factory name encoding as to not include
      // the class-name twice.
      String className = element.enclosingClass.name;
      name = '${className}_${Elements.reconstructConstructorName(element)}';
    } else if (Elements.isStaticOrTopLevel(element)) {
      if (element.isClassMember) {
        ClassElement enclosingClass = element.enclosingClass;
        name = "${enclosingClass.name}_"
               "${element.name}";
      } else {
        name = element.name.replaceAll('+', '_');
      }
    } else if (element.isLibrary) {
      LibraryElement library = element;
      name = libraryLongNames[library];
      if (name != null) return name;
      name = library.getLibraryOrScriptName();
      if (name.contains('.')) {
        // For libraries that have a library tag, we use the last part
        // of the fully qualified name as their base name. For all other
        // libraries, we use the first part of their filename.
        name = library.hasLibraryName()
            ? name.substring(name.lastIndexOf('.') + 1)
            : name.substring(0, name.indexOf('.'));
      }
      // The filename based name can contain all kinds of nasty characters. Make
      // sure it is an identifier.
      if (!IDENTIFIER.hasMatch(name)) {
        name = name.replaceAllMapped(NON_IDENTIFIER_CHAR,
            (match) => match[0].codeUnitAt(0).toRadixString(16));
        if (!IDENTIFIER.hasMatch(name)) {  // e.g. starts with digit.
          name = 'lib_$name';
        }
      }
      // Names constructed based on a libary name will be further disambiguated.
      // However, as names from the same libary should have the same libary
      // name part, we disambiguate the library name here.
      String disambiguated  = name;
      for (int c = 0; libraryLongNames.containsValue(disambiguated); c++) {
        disambiguated = "$name$c";
      }
      libraryLongNames[library] = disambiguated;
      name = disambiguated;
    } else {
      name = element.name;
    }
    return name;
  }

  String suffixForGetInterceptor(Iterable<ClassElement> classes) {
    String abbreviate(ClassElement cls) {
      if (cls == compiler.objectClass) return "o";
      if (cls == backend.jsStringClass) return "s";
      if (cls == backend.jsArrayClass) return "a";
      if (cls == backend.jsDoubleClass) return "d";
      if (cls == backend.jsIntClass) return "i";
      if (cls == backend.jsNumberClass) return "n";
      if (cls == backend.jsNullClass) return "u";
      if (cls == backend.jsBoolClass) return "b";
      if (cls == backend.jsInterceptorClass) return "I";
      return cls.name;
    }
    List<String> names = classes
        .where((cls) => !Elements.isNativeOrExtendsNative(cls))
        .map(abbreviate)
        .toList();
    // There is one dispatch mechanism for all native classes.
    if (classes.any((cls) => Elements.isNativeOrExtendsNative(cls))) {
      names.add("x");
    }
    // Sort the names of the classes after abbreviating them to ensure
    // the suffix is stable and predictable for the suggested names.
    names.sort();
    return names.join();
  }

  /// Property name used for `getInterceptor` or one of its specializations.
  jsAst.Name nameForGetInterceptor(Iterable<ClassElement> classes) {
    FunctionElement getInterceptor = backend.getInterceptorMethod;
    if (classes.contains(backend.jsInterceptorClass)) {
      // If the base Interceptor class is in the set of intercepted classes, we
      // need to go through the generic getInterceptorMethod, since any subclass
      // of the base Interceptor could match.
      // The unspecialized getInterceptor method can also be accessed through
      // its element, so we treat this as a user-space global instead of an
      // internal global.
      return _disambiguateGlobal(getInterceptor);
    }
    String suffix = suffixForGetInterceptor(classes);
    return _disambiguateInternalGlobal("${getInterceptor.name}\$$suffix");
  }

  /// Property name used for the one-shot interceptor method for the given
  /// [selector] and return-type specialization.
  jsAst.Name nameForGetOneShotInterceptor(Selector selector,
                                          Iterable<ClassElement> classes) {
    // The one-shot name is a global name derived from the invocation name.  To
    // avoid instability we would like the names to be unique and not clash with
    // other global names.
    jsAst.Name root = invocationName(selector);

    if (classes.contains(backend.jsInterceptorClass)) {
      // If the base Interceptor class is in the set of intercepted classes,
      // this is the most general specialization which uses the generic
      // getInterceptor method.
      // TODO(sra): Find a way to get the simple name when Object is not in the
      // set of classes for most general variant, e.g. "$lt$n" could be "$lt".
      return new CompoundName([root, _literalDollar]);
    } else {
      String suffix = suffixForGetInterceptor(classes);
      return new CompoundName([root, _literalDollar,
                               new StringBackedName(suffix)]);
    }
  }

  /// Returns the runtime name for [element].
  ///
  /// This name is used as the basis for deriving `is` and `as` property names
  /// for the given type.
  ///
  /// The result is not always safe as a property name unless prefixing
  /// [operatorIsPrefix] or [operatorAsPrefix]. If this is a function type,
  /// then by convention, an underscore must also separate [operatorIsPrefix]
  /// from the type name.
  jsAst.Name runtimeTypeName(TypeDeclarationElement element) {
    if (element == null) return _literalDynamic;
    // The returned name affects both the global and instance member namespaces:
    //
    // - If given a class, this must coincide with the class name, which
    //   is also the GLOBAL property name of its constructor.
    //
    // - The result is used to derive `$isX` and `$asX` names, which are used
    //   as INSTANCE property names.
    //
    // To prevent clashes in both namespaces at once, we disambiguate the name
    // as a global here, and in [_sanitizeForAnnotations] we ensure that
    // ordinary instance members cannot start with `$is` or `$as`.
    return _disambiguateGlobal(element);
  }

  /// Returns the disambiguated name of [class_].
  ///
  /// This is both the *runtime type* of the class (see [runtimeTypeName])
  /// and a global property name in which to store its JS constructor.
  jsAst.Name className(ClassElement class_) => _disambiguateGlobal(class_);

  /// Property name on which [member] can be accessed directly,
  /// without clashing with another JS property name.
  ///
  /// This is used for implementing super-calls, where ordinary dispatch
  /// semantics must be circumvented. For example:
  ///
  ///     class A { foo() }
  ///     class B extends A {
  ///         foo() { super.foo() }
  ///     }
  ///
  /// Example translation to JS:
  ///
  ///     A.prototype.super$A$foo = function() {...}
  ///     A.prototype.foo$0 = A.prototype.super$A$foo
  ///
  ///     B.prototype.foo$0 = function() {
  ///         this.super$A$foo(); // super.foo()
  ///     }
  ///
  jsAst.Name aliasedSuperMemberPropertyName(Element member) {
    assert(!member.isField); // Fields do not need super aliases.
    return _disambiguateInternalMember(member, () {
      String invocationName = operatorNameToIdentifier(member.name);
      return "super\$${member.enclosingClass.name}\$$invocationName";
    });
  }

  /// Property name in which to store the given static or instance [method].
  /// For instance methods, this includes the suffix encoding arity and named
  /// parameters.
  ///
  /// The name is not necessarily unique to [method], since a static method
  /// may share its name with an instance method.
  jsAst.Name methodPropertyName(Element method) {
    return method.isInstanceMember
        ? instanceMethodName(method)
        : globalPropertyName(method);
  }

  /// Returns true if [element] is stored in the static state holder
  /// ([staticStateHolder]).  We intend to store only mutable static state
  /// there, whereas constants are stored in 'C'. Functions, accessors,
  /// classes, etc. are stored in one of the other objects in
  /// [reservedGlobalObjectNames].
  bool _isPropertyOfStaticStateHolder(Element element) {
    // TODO(ahe): Make sure this method's documentation is always true and
    // remove the word "intend".
    return
        // TODO(ahe): Re-write these tests to be positive (so it only returns
        // true for static/top-level mutable fields). Right now, a number of
        // other elements, such as bound closures also live in
        // [staticStateHolder].
        !element.isAccessor &&
        !element.isClass &&
        !element.isTypedef &&
        !element.isConstructor &&
        !element.isFunction &&
        !element.isLibrary;
  }

  /// Returns [staticStateHolder] or one of [reservedGlobalObjectNames].
  String globalObjectFor(Element element) {
    if (_isPropertyOfStaticStateHolder(element)) return staticStateHolder;
    LibraryElement library = element.library;
    if (library == backend.interceptorsLibrary) return 'J';
    if (library.isInternalLibrary) return 'H';
    if (library.isPlatformLibrary) {
      if ('${library.canonicalUri}' == 'dart:html') return 'W';
      return 'P';
    }
    return userGlobalObjects[
        library.getLibraryOrScriptName().hashCode % userGlobalObjects.length];
  }

  jsAst.Name deriveLazyInitializerName(jsAst.Name name) {
    // These are not real dart getters, so do not use GetterName;
    return new CompoundName([_literalLazyGetterPrefix, name]);
  }

  jsAst.Name lazyInitializerName(Element element) {
    assert(Elements.isStaticOrTopLevelField(element));
    jsAst.Name name = _disambiguateGlobal(element);
    // These are not real dart getters, so do not use GetterName;
    return deriveLazyInitializerName(name);
  }

  jsAst.Name staticClosureName(Element element) {
    assert(Elements.isStaticOrTopLevelFunction(element));
    String enclosing = element.enclosingClass == null
        ? "" : element.enclosingClass.name;
    String library = _proposeNameForGlobal(element.library);
    return _disambiguateInternalGlobal(
        "${library}_${enclosing}_${element.name}\$closure");
  }

  // This name is used as part of the name of a TypeConstant
  String uniqueNameForTypeConstantElement(Element element) {
    // TODO(sra): If we replace the period with an identifier character,
    // TypeConstants will have better names in unminified code.
    String library = _proposeNameForGlobal(element.library);
    return "${library}.${element.name}";
  }

  String globalObjectForConstant(ConstantValue constant) => 'C';

  String get operatorIsPrefix => r'$is';

  String get operatorAsPrefix => r'$as';

  String get operatorSignature => r'$signature';

  String get typedefTag => r'typedef';

  String get functionTypeTag => r'func';

  String get functionTypeVoidReturnTag => r'void';

  String get functionTypeReturnTypeTag => r'ret';

  String get functionTypeRequiredParametersTag => r'args';

  String get functionTypeOptionalParametersTag => r'opt';

  String get functionTypeNamedParametersTag => r'named';

  Map<FunctionType, jsAst.Name> functionTypeNameMap =
      new HashMap<FunctionType, jsAst.Name>();
  final FunctionTypeNamer functionTypeNamer;

  jsAst.Name getFunctionTypeName(FunctionType functionType) {
    return functionTypeNameMap.putIfAbsent(functionType, () {
      String proposedName = functionTypeNamer.computeName(functionType);
      return getFreshName(NamingScope.instance, proposedName);
    });
  }

  jsAst.Name operatorIsType(DartType type) {
    if (type.isFunctionType) {
      // TODO(erikcorry): Reduce from $isx to ix when we are minifying.
      return new CompoundName([new StringBackedName(operatorIsPrefix),
                               _literalUnderscore,
                               getFunctionTypeName(type)]);
    }
    return operatorIs(type.element);
  }

  jsAst.Name operatorIs(ClassElement element) {
    // TODO(erikcorry): Reduce from $isx to ix when we are minifying.
    return new CompoundName([new StringBackedName(operatorIsPrefix),
                             runtimeTypeName(element)]);
  }

  /// Returns a name that does not clash with reserved JS keywords.
  String _sanitizeForKeywords(String name) {
    if (jsReserved.contains(name)) {
      name = '\$$name';
    }
    assert(!jsReserved.contains(name));
    return name;
  }

  jsAst.Name substitutionName(Element element) {
    return new CompoundName([new StringBackedName(operatorAsPrefix),
                             runtimeTypeName(element)]);
  }

  /// Translates a [String] into the corresponding [Name] data structure as
  /// used by the namer.
  ///
  /// If [name] is a setter or getter name, the corresponding [GetterName] or
  /// [SetterName] data structure is used.
  jsAst.Name asName(String name) {
    if (name.startsWith(getterPrefix) && name.length > getterPrefix.length) {
      return new GetterName(_literalGetterPrefix,
                           new StringBackedName(
                               name.substring(getterPrefix.length)));
    }
    if (name.startsWith(setterPrefix) && name.length > setterPrefix.length) {
      return new GetterName(_literalSetterPrefix,
                            new StringBackedName(
                                name.substring(setterPrefix.length)));
    }

    return new StringBackedName(name);
  }

  /// Returns a variable name that cannot clash with a keyword, a global
  /// variable, or any name starting with a single '$'.
  ///
  /// Furthermore, this function is injective, that is, it never returns the
  /// same name for two different inputs.
  String safeVariableName(String name) {
    if (jsVariableReserved.contains(name) || name.startsWith(r'$')) {
      return '\$$name';
    }
    return name;
  }

  /// Returns a safe variable name for use in async rewriting.
  ///
  /// Has the same property as [safeVariableName] but does not clash with
  /// names returned from there.
  /// Additionally, when used as a prefix to a variable name, the result
  /// will be safe to use, as well.
  String safeVariablePrefixForAsyncRewrite(String name) {
    return "$asyncPrefix$name";
  }

  jsAst.Name deriveAsyncBodyName(jsAst.Name original) {
    return new _AsyncName(_literalAsyncPrefix, original);
  }

  String operatorNameToIdentifier(String name) {
    if (name == null) return null;
    if (name == '==') {
      return r'$eq';
    } else if (name == '~') {
      return r'$not';
    } else if (name == '[]') {
      return r'$index';
    } else if (name == '[]=') {
      return r'$indexSet';
    } else if (name == '*') {
      return r'$mul';
    } else if (name == '/') {
      return r'$div';
    } else if (name == '%') {
      return r'$mod';
    } else if (name == '~/') {
      return r'$tdiv';
    } else if (name == '+') {
      return r'$add';
    } else if (name == '<<') {
      return r'$shl';
    } else if (name == '>>') {
      return r'$shr';
    } else if (name == '>=') {
      return r'$ge';
    } else if (name == '>') {
      return r'$gt';
    } else if (name == '<=') {
      return r'$le';
    } else if (name == '<') {
      return r'$lt';
    } else if (name == '&') {
      return r'$and';
    } else if (name == '^') {
      return r'$xor';
    } else if (name == '|') {
      return r'$or';
    } else if (name == '-') {
      return r'$sub';
    } else if (name == 'unary-') {
      return r'$negate';
    } else {
      return name;
    }
  }

  String get incrementalHelperName => r'$dart_unsafe_incremental_support';

  jsAst.Expression get accessIncrementalHelper {
    return js('self.${incrementalHelperName}');
  }

  void forgetElement(Element element) {
    jsAst.Name globalName = userGlobals[element];
    invariant(element, globalName != null, message: 'No global name.');
    usedGlobalNames.remove(globalName);
    userGlobals.remove(element);
  }
}

/**
 * Generator of names for [ConstantValue] values.
 *
 * The names are stable under perturbations of the source.  The name is either a
 * short sequence of words, if this can be found from the constant, or a type
 * followed by a hash tag.
 *
 *     List_imX                // A List, with hash tag.
 *     C_Sentinel              // const Sentinel(),  "C_" added to avoid clash
 *                             //   with class name.
 *     JSInt_methods           // an interceptor.
 *     Duration_16000          // const Duration(milliseconds: 16)
 *     EventKeyProvider_keyup  // const EventKeyProvider('keyup')
 *
 */
class ConstantNamingVisitor implements ConstantValueVisitor {

  static final RegExp IDENTIFIER = new RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
  static const MAX_FRAGMENTS = 5;
  static const MAX_EXTRA_LENGTH = 30;
  static const DEFAULT_TAG_LENGTH = 3;

  final Compiler compiler;
  final ConstantCanonicalHasher hasher;

  String root = null;     // First word, usually a type name.
  bool failed = false;    // Failed to generate something pretty.
  List<String> fragments = <String>[];
  int length = 0;

  ConstantNamingVisitor(this.compiler, this.hasher);

  String getName(ConstantValue constant) {
    _visit(constant);
    if (root == null) return 'CONSTANT';
    if (failed) return '${root}_${getHashTag(constant, DEFAULT_TAG_LENGTH)}';
    if (fragments.length == 1) return 'C_${root}';
    return fragments.join('_');
  }

  String getHashTag(ConstantValue constant, int width) =>
      hashWord(hasher.getHash(constant), width);

  String hashWord(int hash, int length) {
    hash &= 0x1fffffff;
    StringBuffer sb = new StringBuffer();
    for (int i = 0; i < length; i++) {
      int digit = hash % 62;
      sb.write('0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
          [digit]);
      hash ~/= 62;
      if (hash == 0) break;
    }
    return sb.toString();
  }

  void addRoot(String fragment) {
    if (root == null && fragments.isEmpty) {
      root = fragment;
    }
    add(fragment);
  }

  void add(String fragment) {
    assert(fragment.length > 0);
    fragments.add(fragment);
    length += fragment.length;
    if (fragments.length > MAX_FRAGMENTS) failed = true;
    if (root != null && length > root.length + 1 + MAX_EXTRA_LENGTH) {
      failed = true;
    }
  }

  void addIdentifier(String fragment) {
    if (fragment.length <= MAX_EXTRA_LENGTH && IDENTIFIER.hasMatch(fragment)) {
      add(fragment);
    } else {
      failed = true;
    }
  }

  void _visit(ConstantValue constant) {
    constant.accept(this, null);
  }

  @override
  void visitFunction(FunctionConstantValue constant, [_]) {
    add(constant.element.name);
  }

  @override
  void visitNull(NullConstantValue constant, [_]) {
    add('null');
  }

  @override
  void visitInt(IntConstantValue constant, [_]) {
    // No `addRoot` since IntConstants are always inlined.
    if (constant.primitiveValue < 0) {
      add('m${-constant.primitiveValue}');
    } else {
      add('${constant.primitiveValue}');
    }
  }

  @override
  void visitDouble(DoubleConstantValue constant, [_]) {
    failed = true;
  }

  @override
  void visitBool(BoolConstantValue constant, [_]) {
    add(constant.isTrue ? 'true' : 'false');
  }

  @override
  void visitString(StringConstantValue constant, [_]) {
    // No `addRoot` since string constants are always inlined.
    addIdentifier(constant.primitiveValue.slowToString());
  }

  @override
  void visitList(ListConstantValue constant, [_]) {
    // TODO(9476): Incorporate type parameters into name.
    addRoot('List');
    int length = constant.length;
    if (constant.length == 0) {
      add('empty');
    } else if (length >= MAX_FRAGMENTS) {
      failed = true;
    } else {
      for (int i = 0; i < length; i++) {
        _visit(constant.entries[i]);
        if (failed) break;
      }
    }
  }

  @override
  void visitMap(JavaScriptMapConstant constant, [_]) {
    // TODO(9476): Incorporate type parameters into name.
    addRoot('Map');
    if (constant.length == 0) {
      add('empty');
    } else {
      // Using some bits from the keys hash tag groups the names Maps with the
      // same structure.
      add(getHashTag(constant.keyList, 2) + getHashTag(constant, 3));
    }
  }

  @override
  void visitConstructed(ConstructedConstantValue constant, [_]) {
    addRoot(constant.type.element.name);
    for (ConstantValue value in constant.fields.values) {
      _visit(value);
      if (failed) return;
    }
  }

  @override
  void visitType(TypeConstantValue constant, [_]) {
    addRoot('Type');
    DartType type = constant.representedType;
    JavaScriptBackend backend = compiler.backend;
    String name = backend.rti.getTypeRepresentationForTypeConstant(type);
    addIdentifier(name);
  }

  @override
  void visitInterceptor(InterceptorConstantValue constant, [_]) {
    addRoot(constant.dispatchedType.element.name);
    add('methods');
  }

  @override
  void visitSynthetic(SyntheticConstantValue constant, [_]) {
    switch (constant.kind) {
      case SyntheticConstantKind.DUMMY_INTERCEPTOR:
        add('dummy_receiver');
        break;
      case SyntheticConstantKind.TYPEVARIABLE_REFERENCE:
        add('type_variable_reference');
        break;
      case SyntheticConstantKind.NAME:
        add('name');
        break;
      default:
        compiler.internalError(compiler.currentElement,
                               "Unexpected SyntheticConstantValue");
    }
  }

  @override
  void visitDeferred(DeferredConstantValue constant, [_]) {
    addRoot('Deferred');
  }
}

/**
 * Generates canonical hash values for [ConstantValue]s.
 *
 * Unfortunately, [Constant.hashCode] is not stable under minor perturbations,
 * so it can't be used for generating names.  This hasher keeps consistency
 * between runs by basing hash values of the names of elements, rather than
 * their hashCodes.
 */
class ConstantCanonicalHasher implements ConstantValueVisitor<int, Null> {

  static const _MASK = 0x1fffffff;
  static const _UINT32_LIMIT = 4 * 1024 * 1024 * 1024;


  final Compiler compiler;
  final Map<ConstantValue, int> hashes = new Map<ConstantValue, int>();

  ConstantCanonicalHasher(this.compiler);

  int getHash(ConstantValue constant) => _visit(constant);

  int _visit(ConstantValue constant) {
    int hash = hashes[constant];
    if (hash == null) {
      hash = _finish(constant.accept(this, null));
      hashes[constant] = hash;
    }
    return hash;
  }

  @override
  int visitNull(NullConstantValue constant, [_]) => 1;

  @override
  int visitBool(BoolConstantValue constant, [_]) {
    return constant.isTrue ? 2 : 3;
  }

  @override
  int visitFunction(FunctionConstantValue constant, [_]) {
    return _hashString(1, constant.element.name);
  }

  @override
  int visitInt(IntConstantValue constant, [_]) {
    return _hashInt(constant.primitiveValue);
  }

  @override
  int visitDouble(DoubleConstantValue constant, [_]) {
    return _hashDouble(constant.primitiveValue);
  }

  @override
  int visitString(StringConstantValue constant, [_]) {
    return _hashString(2, constant.primitiveValue.slowToString());
  }

  @override
  int visitList(ListConstantValue constant, [_]) {
    return _hashList(constant.length, constant.entries);
  }

  @override
  int visitMap(MapConstantValue constant, [_]) {
    int hash = _hashList(constant.length, constant.keys);
    return _hashList(hash, constant.values);
  }

  @override
  int visitConstructed(ConstructedConstantValue constant, [_]) {
    int hash = _hashString(3, constant.type.element.name);
    for (ConstantValue value in constant.fields.values) {
      hash = _combine(hash, _visit(value));
    }
    return hash;
  }

  @override
  int visitType(TypeConstantValue constant, [_]) {
    DartType type = constant.representedType;
    JavaScriptBackend backend = compiler.backend;
    String name = backend.rti.getTypeRepresentationForTypeConstant(type);
    return _hashString(4, name);
  }

  @override
  int visitInterceptor(InterceptorConstantValue constant, [_]) {
    String typeName = constant.dispatchedType.element.name;
    return _hashString(5, typeName);
  }

  @override
  visitSynthetic(SyntheticConstantValue constant, [_]) {
    switch (constant.kind) {
      case SyntheticConstantKind.TYPEVARIABLE_REFERENCE:
        return constant.payload.hashCode;
      default:
        compiler.internalError(NO_LOCATION_SPANNABLE,
                               'SyntheticConstantValue should never be named and '
                               'never be subconstant');
        return null;
    }
  }

  @override
  int visitDeferred(DeferredConstantValue constant, [_]) {
    int hash = constant.prefix.hashCode;
    return _combine(hash, _visit(constant.referenced));
  }

  int _hashString(int hash, String s) {
    int length = s.length;
    hash = _combine(hash, length);
    // Increasing stride is O(log N) on large strings which are unlikely to have
    // many collisions.
    for (int i = 0; i < length; i += 1 + (i >> 2)) {
      hash = _combine(hash, s.codeUnitAt(i));
    }
    return hash;
  }

  int _hashList(int hash, List<ConstantValue> constants) {
    for (ConstantValue constant in constants) {
      hash = _combine(hash, _visit(constant));
    }
    return hash;
  }

  static int _hashInt(int value) {
    if (value.abs() < _UINT32_LIMIT) return _MASK & value;
    return _hashDouble(value.toDouble());
  }

  static int _hashDouble(double value) {
    double magnitude = value.abs();
    int sign = value < 0 ? 1 : 0;
    if (magnitude < _UINT32_LIMIT) {  // 2^32
      int intValue = value.toInt();
      // Integer valued doubles in 32-bit range hash to the same values as ints.
      int hash = _hashInt(intValue);
      if (value == intValue) return hash;
      hash = _combine(hash, sign);
      int fraction = ((magnitude - intValue.abs()) * (_MASK + 1)).toInt();
      hash = _combine(hash, fraction);
      return hash;
    } else if (value.isInfinite) {
      return _combine(6, sign);
    } else if (value.isNaN) {
      return 7;
    } else {
      int hash = 0;
      while (magnitude >= _UINT32_LIMIT) {
        magnitude = magnitude / _UINT32_LIMIT;
        hash++;
      }
      hash = _combine(hash, sign);
      return _combine(hash, _hashDouble(magnitude));
    }
  }

  /**
   * [_combine] and [_finish] are parts of the [Jenkins hash function][1],
   * modified by using masking to keep values in SMI range.
   *
   * [1]: http://en.wikipedia.org/wiki/Jenkins_hash_function
   */
  static int _combine(int hash, int value) {
    hash = _MASK & (hash + value);
    hash = _MASK & (hash + (((_MASK >> 10) & hash) << 10));
    hash = hash ^ (hash >> 6);
    return hash;
  }

  static int _finish(int hash) {
    hash = _MASK & (hash + (((_MASK >> 3) & hash) <<  3));
    hash = hash & (hash >> 11);
    return _MASK & (hash + (((_MASK >> 15) & hash) << 15));
  }
}

class FunctionTypeNamer extends BaseDartTypeVisitor {
  final Compiler compiler;
  StringBuffer sb;

  FunctionTypeNamer(this.compiler);

  JavaScriptBackend get backend => compiler.backend;

  String computeName(DartType type) {
    sb = new StringBuffer();
    visit(type);
    return sb.toString();
  }

  visit(DartType type, [_]) {
    type.accept(this, null);
  }

  visitType(DartType type, _) {
    sb.write(type.name);
  }

  visitFunctionType(FunctionType type, _) {
    if (backend.rti.isSimpleFunctionType(type)) {
      sb.write('args${type.parameterTypes.length}');
      return;
    }
    visit(type.returnType);
    sb.write('_');
    for (DartType parameter in type.parameterTypes) {
      sb.write('_');
      visit(parameter);
    }
    bool first = false;
    for (DartType parameter in  type.optionalParameterTypes) {
      if (!first) {
        sb.write('_');
      }
      sb.write('_');
      visit(parameter);
      first = true;
    }
    if (!type.namedParameterTypes.isEmpty) {
      first = false;
      for (DartType parameter in type.namedParameterTypes) {
        if (!first) {
          sb.write('_');
        }
        sb.write('_');
        visit(parameter);
        first = true;
      }
    }
  }
}

enum NamingScope {
  global,
  instance,
  constant
}