import "package:stera/src/modules/profile/data/repo/profile_repo.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:flutter/widgets.dart";

class ProfileProvider extends ChangeNotifier {
  bool _isLoggingOut = false;
  bool get isLoggingOut => _isLoggingOut;
  set isLoggingOut(bool value) {
    _isLoggingOut = value;
    notifyListeners();
  }

  bool _isSubmittingFeedback = false;
  bool get isSubmittingFeedback => _isSubmittingFeedback;
  set isSubmittingFeedback(bool value) {
    _isSubmittingFeedback = value;
    notifyListeners();
  }

  Future<Failure?> submitFeedback({
    required String comment,
  }) async {
    isSubmittingFeedback = true;
    final error = await ProfileRepo.submitFeedback(
      comment: comment,
    );
    isSubmittingFeedback = false;
    return error;
  }

  void reset() {
    _isLoggingOut = false;
    _isSubmittingFeedback = false;
    notifyListeners();
  }
}
