import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/access-mode.dart';
import 'package:tinode/src/topic.dart';

/// This is a data structure for user's data in cache
class CacheUser {
  final Map<String, dynamic> public;
  final String userId;
  final AccessMode acs;

  /// Creates a new instance of cache user
  CacheUser(this.public, this.userId, this.acs);

  /// Create a copy of this instance
  CacheUser copy() {
    return CacheUser(public, userId, acs);
  }
}

/// Cache manager is responsible for reading and writing data into cache
class CacheManager {
  /// This map holds the cached data
  final Map<String, TopicSubscription> _users = {};
  final Map<String, Topic> _topics = {};

  Iterable<Topic> get topics => _topics.values;

  /// Executes a function for each element in cache, just like map method on `Map`
  // void map(MapEntry Function(String, dynamic) function) {
  //   _cache.map(function);
  // }

  /// This is a wrapper for `get` function which gets a user from cache by userId
  TopicSubscription? getUser(String userId) => _users[userId];

  /// This is a wrapper for `put` function which puts a user into cache by userId
  void putUser(String userId, TopicSubscription user) => _users[userId] = user;

  /// This is a wrapper for `delete` function which deletes a user from cache by userId
  TopicSubscription? deleteUser(String userId) => _users.remove(userId);

  bool containsUser(String userId) => _users.containsKey(userId);

  Topic? getTopic(String name) {
    return _topics[name];
  }

  /// This is a wrapper for `put` function which puts a topic into cache
  void putTopic(String topicName, Topic topic) => _topics[topicName] = topic;

  /// This is a wrapper for `delete` function which deletes a topic from cache by topic name
  Topic? deleteTopic(String topicName) {
    return _topics.remove(topicName);
  }

  bool containsTopic(String topicName) => _topics.containsKey(topicName);

  void topicsForEach(void Function(String key, Topic topic) action) =>
      _topics.forEach(action);
}
