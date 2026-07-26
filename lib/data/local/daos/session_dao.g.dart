// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_dao.dart';

// ignore_for_file: type=lint
mixin _$SessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $UsersTable get users => attachedDatabase.users;
  $UserOutletAccessesTable get userOutletAccesses =>
      attachedDatabase.userOutletAccesses;
  SessionDaoManager get managers => SessionDaoManager(this);
}

class SessionDaoManager {
  final _$SessionDaoMixin _db;
  SessionDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$UserOutletAccessesTableTableManager get userOutletAccesses =>
      $$UserOutletAccessesTableTableManager(
          _db.attachedDatabase, _db.userOutletAccesses);
}
