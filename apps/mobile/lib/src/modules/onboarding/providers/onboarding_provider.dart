import "package:stera/src/modules/auth/data/models/user.dart";
import "package:stera/src/modules/auth/data/repo/user_repo.dart";
import "package:stera/src/modules/onboarding/data/enums/country.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:flutter/material.dart";

class OnboardingProvider extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController customCountryController = TextEditingController();

  Country _selectedCountry = Country.india;
  Country get selectedCountry => _selectedCountry;
  set selectedCountry(Country value) {
    _selectedCountry = value;
    if (value != Country.other) {
      customCountryController.clear();
    }
    notifyListeners();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  set isLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<(User?, Failure?)> onboardUser() async {
    final err = validateOnboardingData();
    if (err != null) {
      return (null, err);
    }

    isLoading = true;

    final fullName = nameController.text.trim();

    // Register as contributor + set name in a single call.
    // The register endpoint accepts name, city, country, age as optional fields.
    final registerErr = await UserRepo.registerContributor(
      name: fullName,
      country: selectedCountry == Country.other
          ? customCountryController.text.trim()
          : selectedCountry.code,
    );
    if (registerErr != null) {
      isLoading = false;
      return (null, registerErr);
    }

    // The register endpoint returns only the thin contributor row — not the full
    // User shape. Fetch the canonical user (profile + contributor) via GET /auth/me.
    final (user, userErr) = await UserRepo.getMe();

    isLoading = false;

    if (userErr != null) return (null, userErr);

    return (user, null);
  }

  Failure? validateOnboardingData() {
    if (nameController.text.trim().isEmpty) {
      return Failure(code: ErrorType.validation, message: "Name is required");
    }
    if (selectedCountry == Country.other &&
        customCountryController.text.trim().isEmpty) {
      return Failure(
        code: ErrorType.validation,
        message: "Please enter your country",
      );
    }

    return null;
  }

  void reset() {
    nameController.clear();
    customCountryController.clear();
    _selectedCountry = Country.india;
  }

  @override
  void dispose() {
    nameController.dispose();
    customCountryController.dispose();
    super.dispose();
  }
}
