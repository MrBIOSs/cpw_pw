/// Revision status for three content types.
typedef RevisionState = ({
int elementCurrentVer,
int launcherCurrentVer,
int patcherCurrentVer,
});

extension RevisionStateExt on RevisionState {
  int getCurrent(String type) => switch (type) {
    'element' => elementCurrentVer,
    'launcher' => launcherCurrentVer,
    'patcher' => patcherCurrentVer,
    _ => throw ArgumentError('Unknown type: $type'),
  };
}