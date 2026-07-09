// v2: interop tier — exported by advanced.dart, absent from the README.

import '../world/world.dart';
import 'query_1.dart';
import 'query_2.dart';
import 'query_3.dart';
import 'query_4.dart';

/// The classic typed-query constructors, moved verbatim off [World] so the
/// v2 record-query surface can own the `query2`/`query3`/`query4` names
/// (Dart instance members always win over extensions). Existing call sites
/// are source-compatible: `world.query2<A, B>(...)` resolves here wherever
/// this extension is in scope and the record surface is not.
extension ClassicWorldQueries on World {
  /// Creates a single-component query over component type [A].
  Query1<A> query1<A>({
    List<Type> withTypes = const <Type>[],
    List<Type> withoutTypes = const <Type>[],
  }) {
    return Query1<A>(
      this,
      stores.object<A>(),
      withTypes.map(stores.require).toList(growable: false),
      withoutTypes.map(stores.require).toList(growable: false),
    );
  }

  /// Creates a two-component query over component types [A] and [B].
  Query2<A, B> query2<A, B>({
    List<Type> withTypes = const <Type>[],
    List<Type> withoutTypes = const <Type>[],
  }) {
    return Query2<A, B>(
      this,
      stores.object<A>(),
      stores.object<B>(),
      withTypes.map(stores.require).toList(growable: false),
      withoutTypes.map(stores.require).toList(growable: false),
    );
  }

  /// Creates a three-component query over [A], [B] and [C].
  Query3<A, B, C> query3<A, B, C>({
    List<Type> withTypes = const <Type>[],
    List<Type> withoutTypes = const <Type>[],
  }) {
    return Query3<A, B, C>(
      this,
      stores.object<A>(),
      stores.object<B>(),
      stores.object<C>(),
      withTypes.map(stores.require).toList(growable: false),
      withoutTypes.map(stores.require).toList(growable: false),
    );
  }

  /// Creates a four-component query over [A], [B], [C] and [D].
  Query4<A, B, C, D> query4<A, B, C, D>({
    List<Type> withTypes = const <Type>[],
    List<Type> withoutTypes = const <Type>[],
  }) {
    return Query4<A, B, C, D>(
      this,
      stores.object<A>(),
      stores.object<B>(),
      stores.object<C>(),
      stores.object<D>(),
      withTypes.map(stores.require).toList(growable: false),
      withoutTypes.map(stores.require).toList(growable: false),
    );
  }
}
