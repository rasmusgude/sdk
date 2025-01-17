// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This code was auto-generated, is not intended to be edited, and is subject to
// significant change. Please see the README file for more information.

library analyzer.test.generated.source_factory;

import 'dart:convert';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/src/generated/java_core.dart';
import 'package:analyzer/src/generated/java_engine_io.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/generated/utilities_dart.dart' as utils;
import 'package:package_config/packages.dart';
import 'package:package_config/packages_file.dart' as pkgfile show parse;
import 'package:package_config/src/packages_impl.dart';
import 'package:path/path.dart';
import 'package:unittest/unittest.dart';

import '../reflective_tests.dart';
import '../utils.dart';
import 'test_support.dart';

main() {
  initializeTestEnvironment();
  runReflectiveTests(SourceFactoryTest);
  runPackageMapTests();
}

Source createSource({String path, String uri}) =>
    //TODO(pquitslund): find some way to pass an actual URI into source creation
    new MemoryResourceProvider()
        .getFile(path)
        .createSource(uri != null ? Uri.parse(uri) : null);

void runPackageMapTests() {
  final Uri baseUri = new Uri.file('test/base');
  final List<UriResolver> testResolvers = [new FileUriResolver()];

  Packages createPackageMap(Uri base, String configFileContents) {
    List<int> bytes = UTF8.encode(configFileContents);
    Map<String, Uri> map = pkgfile.parse(bytes, base);
    return new MapPackages(map);
  }

  Map<String, List<Folder>> getPackageMap(String config) {
    Packages packages = createPackageMap(baseUri, config);
    SourceFactory factory = new SourceFactory(testResolvers, packages);
    return factory.packageMap;
  }

  String resolvePackageUri(
      {String uri,
      String config,
      Source containingSource,
      UriResolver customResolver}) {
    Packages packages = createPackageMap(baseUri, config);
    List<UriResolver> resolvers = testResolvers.toList();
    if (customResolver != null) {
      resolvers.add(customResolver);
    }
    SourceFactory factory = new SourceFactory(resolvers, packages);
    Source source = factory.resolveUri(containingSource, uri);
    return source != null ? source.fullName : null;
  }

  Uri restorePackageUri(
      {Source source, String config, UriResolver customResolver}) {
    Packages packages = createPackageMap(baseUri, config);
    List<UriResolver> resolvers = testResolvers.toList();
    if (customResolver != null) {
      resolvers.add(customResolver);
    }
    SourceFactory factory = new SourceFactory(resolvers, packages);
    return factory.restoreUri(source);
  }

  group('SourceFactoryTest', () {
    group('package mapping', () {
      group('resolveUri', () {
        test('URI in mapping', () {
          String uri = resolvePackageUri(
              config: '''
unittest:file:///home/somebody/.pub/cache/unittest-0.9.9/lib/
async:file:///home/somebody/.pub/cache/async-1.1.0/lib/
quiver:file:///home/somebody/.pub/cache/quiver-1.2.1/lib
''',
              uri: 'package:unittest/unittest.dart');
          expect(
              uri,
              equals(
                  '/home/somebody/.pub/cache/unittest-0.9.9/lib/unittest.dart'));
        });
        test('URI in mapping (no scheme)', () {
          String uri = resolvePackageUri(
              config: '''
unittest:/home/somebody/.pub/cache/unittest-0.9.9/lib/
async:/home/somebody/.pub/cache/async-1.1.0/lib/
quiver:/home/somebody/.pub/cache/quiver-1.2.1/lib
''',
              uri: 'package:unittest/unittest.dart');
          expect(
              uri,
              equals(
                  '/home/somebody/.pub/cache/unittest-0.9.9/lib/unittest.dart'));
        });
        test('URI not in mapping', () {
          String uri = resolvePackageUri(
              config: 'unittest:/home/somebody/.pub/cache/unittest-0.9.9/lib/',
              uri: 'package:foo/foo.dart');
          expect(uri, isNull);
        });
        test('Non-package URI', () {
          var testResolver = new CustomUriResolver(uriPath: 'test_uri');
          String uri = resolvePackageUri(
              config: 'unittest:/home/somebody/.pub/cache/unittest-0.9.9/lib/',
              uri: 'custom:custom.dart',
              customResolver: testResolver);
          expect(uri, testResolver.uriPath);
        });
        test('Invalid URI', () {
          // TODO(pquitslund): fix clients to handle errors appropriately
          //   CLI: print message 'invalid package file format'
          //   SERVER: best case tell user somehow and recover...
          expect(
              () => resolvePackageUri(
                  config: 'foo:<:&%>', uri: 'package:foo/bar.dart'),
              throwsA(new isInstanceOf('FormatException')));
        });
        test('Valid URI that cannot be further resolved', () {
          String uri = resolvePackageUri(
              config: 'foo:http://www.google.com', uri: 'package:foo/bar.dart');
          expect(uri, isNull);
        });
        test('Relative URIs', () {
          Source containingSource = createSource(
              path: '/foo/bar/baz/foo.dart', uri: 'package:foo/foo.dart');
          String uri = resolvePackageUri(
              config: 'foo:/foo/bar/baz',
              uri: 'bar.dart',
              containingSource: containingSource);
          expect(uri, isNotNull);
          expect(uri, equals('/foo/bar/baz/bar.dart'));
        });
      });
      group('restoreUri', () {
        test('URI in mapping', () {
          Uri uri = restorePackageUri(
              config: '''
unittest:/home/somebody/.pub/cache/unittest-0.9.9/lib/
async:/home/somebody/.pub/cache/async-1.1.0/lib/
quiver:/home/somebody/.pub/cache/quiver-1.2.1/lib
''',
              source: new FileBasedSource(FileUtilities2.createFile(
                  '/home/somebody/.pub/cache/unittest-0.9.9/lib/unittest.dart')));
          expect(uri, isNotNull);
          expect(uri.toString(), equals('package:unittest/unittest.dart'));
        });
      });
      group('packageMap', () {
        test('non-file URIs filtered', () {
          Map<String, List<Folder>> map = getPackageMap('''
quiver:/home/somebody/.pub/cache/quiver-1.2.1/lib
foo:http://www.google.com
''');
          expect(map.keys, unorderedEquals(['quiver']));
        });
      });
    });
  });

  group('URI utils', () {
    group('URI', () {
      test('startsWith', () {
        expect(utils.startsWith(Uri.parse('/foo/bar/'), Uri.parse('/foo/')),
            isTrue);
        expect(utils.startsWith(Uri.parse('/foo/bar/'), Uri.parse('/foo/bar/')),
            isTrue);
        expect(utils.startsWith(Uri.parse('/foo/bar'), Uri.parse('/foo/b')),
            isFalse);
      });
    });
  });
}

class CustomUriResolver extends UriResolver {
  String uriPath;
  CustomUriResolver({this.uriPath});

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) =>
      createSource(path: uriPath);
}

@reflectiveTest
class SourceFactoryTest {
  void test_creation() {
    expect(new SourceFactory([]), isNotNull);
  }

  void test_fromEncoding_invalidUri() {
    SourceFactory factory = new SourceFactory([]);
    expect(() => factory.fromEncoding("<:&%>"),
        throwsA(new isInstanceOf<IllegalArgumentException>()));
  }

  void test_fromEncoding_noResolver() {
    SourceFactory factory = new SourceFactory([]);
    expect(() => factory.fromEncoding("foo:/does/not/exist.dart"),
        throwsA(new isInstanceOf<IllegalArgumentException>()));
  }

  void test_fromEncoding_valid() {
    String encoding = "file:///does/not/exist.dart";
    SourceFactory factory = new SourceFactory(
        [new UriResolver_SourceFactoryTest_test_fromEncoding_valid(encoding)]);
    expect(factory.fromEncoding(encoding), isNotNull);
  }

  void test_resolveUri_absolute() {
    UriResolver_absolute resolver = new UriResolver_absolute();
    SourceFactory factory = new SourceFactory([resolver]);
    factory.resolveUri(null, "dart:core");
    expect(resolver.invoked, isTrue);
  }

  void test_resolveUri_nonAbsolute_absolute() {
    SourceFactory factory =
        new SourceFactory([new UriResolver_nonAbsolute_absolute()]);
    String absolutePath = "/does/not/matter.dart";
    Source containingSource =
        new FileBasedSource(FileUtilities2.createFile("/does/not/exist.dart"));
    Source result = factory.resolveUri(containingSource, absolutePath);
    expect(result.fullName,
        FileUtilities2.createFile(absolutePath).getAbsolutePath());
  }

  void test_resolveUri_nonAbsolute_relative() {
    SourceFactory factory =
        new SourceFactory([new UriResolver_nonAbsolute_relative()]);
    Source containingSource =
        new FileBasedSource(FileUtilities2.createFile("/does/not/have.dart"));
    Source result = factory.resolveUri(containingSource, "exist.dart");
    expect(result.fullName,
        FileUtilities2.createFile("/does/not/exist.dart").getAbsolutePath());
  }

  void test_resolveUri_nonAbsolute_relative_package() {
    MemoryResourceProvider provider = new MemoryResourceProvider();
    Context context = provider.pathContext;
    String packagePath =
        context.joinAll([context.separator, 'path', 'to', 'package']);
    String libPath = context.joinAll([packagePath, 'lib']);
    String dirPath = context.joinAll([libPath, 'dir']);
    String firstPath = context.joinAll([dirPath, 'first.dart']);
    String secondPath = context.joinAll([dirPath, 'second.dart']);

    provider.newFolder(packagePath);
    Folder libFolder = provider.newFolder(libPath);
    provider.newFolder(dirPath);
    File firstFile = provider.newFile(firstPath, '');
    provider.newFile(secondPath, '');

    PackageMapUriResolver resolver = new PackageMapUriResolver(provider, {
      'package': [libFolder]
    });
    SourceFactory factory = new SourceFactory([resolver]);
    Source librarySource =
        firstFile.createSource(Uri.parse('package:package/dir/first.dart'));

    Source result = factory.resolveUri(librarySource, 'second.dart');
    expect(result, isNotNull);
    expect(result.fullName, secondPath);
    expect(result.uri.toString(), 'package:package/dir/second.dart');
  }

  void test_restoreUri() {
    JavaFile file1 = FileUtilities2.createFile("/some/file1.dart");
    JavaFile file2 = FileUtilities2.createFile("/some/file2.dart");
    Source source1 = new FileBasedSource(file1);
    Source source2 = new FileBasedSource(file2);
    Uri expected1 = parseUriWithException("file:///my_file.dart");
    SourceFactory factory =
        new SourceFactory([new UriResolver_restoreUri(source1, expected1)]);
    expect(factory.restoreUri(source1), same(expected1));
    expect(factory.restoreUri(source2), same(null));
  }
}

class UriResolver_absolute extends UriResolver {
  bool invoked = false;

  UriResolver_absolute();

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) {
    invoked = true;
    return null;
  }
}

class UriResolver_nonAbsolute_absolute extends UriResolver {
  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) {
    return new FileBasedSource(new JavaFile.fromUri(uri), actualUri);
  }
}

class UriResolver_nonAbsolute_relative extends UriResolver {
  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) {
    return new FileBasedSource(new JavaFile.fromUri(uri), actualUri);
  }
}

class UriResolver_restoreUri extends UriResolver {
  Source source1;
  Uri expected1;
  UriResolver_restoreUri(this.source1, this.expected1);

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) => null;

  @override
  Uri restoreAbsolute(Source source) {
    if (identical(source, source1)) {
      return expected1;
    }
    return null;
  }
}

class UriResolver_SourceFactoryTest_test_fromEncoding_valid
    extends UriResolver {
  String encoding;
  UriResolver_SourceFactoryTest_test_fromEncoding_valid(this.encoding);

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) {
    if (uri.toString() == encoding) {
      return new TestSource();
    }
    return null;
  }
}
