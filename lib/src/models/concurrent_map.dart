import 'package:synchronized/synchronized.dart';

class ConcurrentMap<K, V> {
  final Map<K, V> _map = {};
  final Lock _lock = Lock();

  ConcurrentMap();

  Future<bool> containsValue(Object? value) {
    return _lock.synchronized(() => _map.containsValue(value));
  }

  Future<bool> containsKey(Object? key) =>
      _lock.synchronized(() => _map.containsKey(key));

  Future<V?> get(Object? key) => _lock.synchronized(() => _map[key]);

  Future<void> set(K key, V value) =>
      _lock.synchronized(() => _map[key] = value);

  Future<Iterable<MapEntry<K, V>>> get entries =>
      _lock.synchronized(() => _map.entries);

  Future<Map<K2, V2>> map<K2, V2>(
    MapEntry<K2, V2> Function(K key, V value) convert,
  ) => _lock.synchronized(() => _map.map(convert));

  Future<void> addEntries(Iterable<MapEntry<K, V>> newEntries) =>
      _lock.synchronized(() => _map.addEntries(newEntries));

  Future<V> update(
    K key,
    V Function(V value) update, {
    V Function()? ifAbsent,
  }) => _lock.synchronized(() => _map.update(key, update, ifAbsent: ifAbsent));

  Future<void> updateAll(V Function(K key, V value) update) =>
      _lock.synchronized(() => _map.updateAll(update));

  Future<void> removeWhere(bool Function(K key, V value) test) =>
      _lock.synchronized(() => _map.removeWhere(test));

  Future<V> putIfAbsent(K key, V Function() ifAbsent) =>
      _lock.synchronized(() => _map.putIfAbsent(key, ifAbsent));

  Future<void> addAll(Map<K, V> other) =>
      _lock.synchronized(() => _map.addAll(other));

  Future<V?> remove(Object? key) => _lock.synchronized(() => _map.remove(key));

  Future<void> clear() => _lock.synchronized(() => _map.clear());

  Future<void> forEach(void Function(K key, V value) action) =>
      _lock.synchronized(() => _map.forEach(action));

  Future<Iterable<K>> get keys => _lock.synchronized(() => _map.keys);

  Future<Iterable<V>> get values => _lock.synchronized(() => _map.values);

  Future<int> get length => _lock.synchronized(() => _map.length);

  Future<bool> get isEmpty => _lock.synchronized(() => _map.isEmpty);

  Future<bool> get isNotEmpty => _lock.synchronized(() => _map.isNotEmpty);
}
