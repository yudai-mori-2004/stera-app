import "package:stera/src/services/db/db.dart";
import "package:flutter/foundation.dart";

class UploadSelectionManager extends ChangeNotifier {
  final Set<int> _selectedIds = {};

  Set<int> get selectedIds => _selectedIds;

  bool get hasSelection => _selectedIds.isNotEmpty;

  int get selectionCount => _selectedIds.length;

  void selectUpload(Upload upload) {
    _selectedIds.add(upload.id);
    notifyListeners();
  }

  void selectUploads(Iterable<Upload> uploads) {
    final added = uploads.where((u) => _selectedIds.add(u.id)).isNotEmpty;
    if (added) notifyListeners();
  }

  void deselectUpload(Upload upload) {
    _selectedIds.remove(upload.id);
    notifyListeners();
  }

  void deselectById(int id) {
    selectedIds.remove(id);
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  bool isSelected(Upload upload) => _selectedIds.contains(upload.id);

  void toggleSelection(Upload upload) {
    if (isSelected(upload)) {
      deselectUpload(upload);
    } else {
      selectUpload(upload);
    }
  }

  /// Remove IDs that match the predicate
  void removeWhere(bool Function(int id) test) {
    final toRemove = _selectedIds.where(test).toList();
    if (toRemove.isNotEmpty) {
      _selectedIds.removeAll(toRemove);
      notifyListeners();
    }
  }
}
