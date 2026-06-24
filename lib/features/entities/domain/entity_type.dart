// ignore_for_file: constant_identifier_names
enum EntityType {
  INTESHAR,
  AGENT1,
  AGENT2,
  STORE,
}

extension EntityTypeX on EntityType {
  String get label {
    switch (this) {
      case EntityType.INTESHAR:
        return 'HQ';
      case EntityType.AGENT1:
        return 'Main Agent';
      case EntityType.AGENT2:
        return 'Sub Agent';
      case EntityType.STORE:
        return 'Store';
    }
  }

  String get homeRoute {
    switch (this) {
      case EntityType.INTESHAR:
        return '/hq/home';
      case EntityType.AGENT1:
        return '/agent1/home';
      case EntityType.AGENT2:
        return '/agent2/home';
      case EntityType.STORE:
        return '/store/home';
    }
  }
}

enum UserRole { USER, ADMIN }
