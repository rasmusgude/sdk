// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of types;

/**
 * A type mask represents a set of concrete types, but the operations
 * on it are not guaranteed to be precise. When computing the union of
 * two masks you may get a mask that is too wide (like a common
 * superclass instead of a proper union type) and when computing the
 * intersection of two masks you may get a mask that is too narrow.
 */
class TypeMask {

  static const int EXACT    = 0;
  static const int SUBCLASS = 1;
  static const int SUBTYPE  = 2;

  final DartType base;
  final int flags;

  TypeMask(DartType base, int kind, bool isNullable)
      : this.internal(base, (kind << 1) | (isNullable ? 1 : 0));

  const TypeMask.exact(DartType base)
      : this.internal(base, (EXACT << 1) | 1);
  const TypeMask.subclass(DartType base)
      : this.internal(base, (SUBCLASS << 1) | 1);
  const TypeMask.subtype(DartType base)
      : this.internal(base, (SUBTYPE << 1) | 1);

  const TypeMask.nonNullExact(DartType base)
      : this.internal(base, EXACT << 1);
  const TypeMask.nonNullSubclass(DartType base)
      : this.internal(base, SUBCLASS << 1);
  const TypeMask.nonNullSubtype(DartType base)
      : this.internal(base, SUBTYPE << 1);

  const TypeMask.internal(this.base, this.flags);

  bool get isNullable => (flags & 1) != 0;
  bool get isExact => (flags >> 1) == EXACT;

  // TODO(kasperl): Get rid of these. They should not be a visible
  // part of the implementation because they make it hard to add
  // proper union types if we ever want to.
  bool get isSubclass => (flags >> 1) == SUBCLASS;
  bool get isSubtype => (flags >> 1) == SUBTYPE;

  /**
   * Returns a nullable variant of [this] type mask.
   */
  TypeMask nullable() {
    return isNullable ? this : new TypeMask.internal(base, flags | 1);
  }

  /**
   * Returns whether or not this type mask contains the given type.
   */
  bool contains(DartType type, Compiler compiler) {
    // TODO(kasperl): Do this error handling earlier.
    if (base.kind != TypeKind.INTERFACE) return false;
    assert(type.kind == TypeKind.INTERFACE);
    // Compare the interface types.
    ClassElement baseElement = base.element;
    ClassElement typeElement = type.element;
    if (isExact) {
      return identical(baseElement, typeElement);
    } else if (isSubclass) {
      return typeElement.isSubclassOf(baseElement);
    } else {
      assert(isSubtype);
      Set<ClassElement> subtypes = compiler.world.subtypes[baseElement];
      return subtypes != null ? subtypes.contains(typeElement) : false;
    }
  }

  // TODO(kasperl): Try to get rid of this method. It shouldn't really
  // be necessary.
  bool containsAll(Compiler compiler) {
    // TODO(kasperl): Do this error handling earlier.
    if (base.kind != TypeKind.INTERFACE) return false;
    // TODO(kasperl): Should we take nullability into account here?
    if (isExact) return false;
    ClassElement baseElement = base.element;
    return identical(baseElement, compiler.objectClass)
        || identical(baseElement, compiler.dynamicClass);
  }

  // TODO(kasperl): This implementation is a bit sketchy, but it
  // behaves the same as the old implementation on HType. The plan is
  // to extend this and add proper testing of it.
  TypeMask union(TypeMask other, Types types) {
    // TODO(kasperl): Add subclass handling.
    if (base == other.base) {
      return unionSame(other, types);
    } else if (types.isSubtype(other.base, base)) {
      return unionSubtype(other, types);
    } else if (types.isSubtype(base, other.base)) {
      return other.unionSubtype(this, types);
    }
    return null;
  }

  TypeMask unionSame(TypeMask other, Types types) {
    assert(base == other.base);
    // The two masks share the base type, so we must chose the least
    // constraining kind (the highest) of the two. If either one of
    // the masks are nullable the result should be nullable too.
    int combined = (flags > other.flags)
        ? flags | (other.flags & 1)
        : other.flags | (flags & 1);
    if (flags == combined) {
      return this;
    } else if (other.flags == combined) {
      return other;
    } else {
      return new TypeMask.internal(base, combined);
    }
  }

  TypeMask unionSubtype(TypeMask other, Types types) {
    assert(types.isSubtype(other.base, base));
    // Since the other mask is a subtype of this mask, we need the
    // resulting union to be a subtype too. If either one of the masks
    // are nullable the result should be nullable too.
    int combined = (SUBTYPE << 1) | ((flags | other.flags) & 1);
    return (flags != combined)
        ? new TypeMask.internal(base, combined)
        : this;
  }

  // TODO(kasperl): This implementation is a bit sketchy, but it
  // behaves the same as the old implementation on HType. The plan is
  // to extend this and add proper testing of it.
  TypeMask intersection(TypeMask other, Types types) {
    int combined = (flags < other.flags)
        ? flags & ((other.flags & 1) | ~1)
        : other.flags & ((flags & 1) | ~1);
    if (base == other.base) {
      if (flags == combined) {
        return this;
      } else if (other.flags == combined) {
        return other;
      } else {
        return new TypeMask.internal(base, combined);
      }
    } else if (types.isSubtype(other.base, base)) {
      if (other.flags == combined) {
        return other;
      } else {
        return new TypeMask.internal(other.base, combined);
      }
    } else if (types.isSubtype(base, other.base)) {
      if (flags == combined) {
        return this;
      } else {
        return new TypeMask.internal(base, combined);
      }
    }
    return null;
  }

  bool operator ==(var other) {
    if (other is !TypeMask) return false;
    TypeMask otherMask = other;
    return (base == otherMask.base) && (flags == otherMask.flags);
  }

  String toString() {
    StringBuffer buffer = new StringBuffer();
    if (isNullable) buffer.write('null|');
    if (isExact) buffer.write('exact=');
    if (isSubclass) buffer.write('subclass=');
    if (isSubtype) buffer.write('subtype=');
    buffer.write(base.element.name.slowToString());
    return "[$buffer]";
  }
}