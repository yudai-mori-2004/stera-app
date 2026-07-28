enum Country {
  india,
  china,
  unitedStates,
  unitedKingdom,
  canada,
  australia,
  germany,
  france,
  japan,
  singapore,
  unitedArabEmirates,
  other,
}

extension CountryX on Country {
  String get code {
    switch (this) {
      case Country.india:
        return "IN";
      case Country.china:
        return "CN";
      case Country.unitedStates:
        return "US";
      case Country.unitedKingdom:
        return "GB";
      case Country.canada:
        return "CA";
      case Country.australia:
        return "AU";
      case Country.germany:
        return "DE";
      case Country.france:
        return "FR";
      case Country.japan:
        return "JP";
      case Country.singapore:
        return "SG";
      case Country.unitedArabEmirates:
        return "AE";
      case Country.other:
        return "OTHER";
    }
  }

  String get name {
    switch (this) {
      case Country.india:
        return "India";
      case Country.china:
        return "China";
      case Country.unitedStates:
        return "United States";
      case Country.unitedKingdom:
        return "United Kingdom";
      case Country.canada:
        return "Canada";
      case Country.australia:
        return "Australia";
      case Country.germany:
        return "Germany";
      case Country.france:
        return "France";
      case Country.japan:
        return "Japan";
      case Country.singapore:
        return "Singapore";
      case Country.unitedArabEmirates:
        return "United Arab Emirates";
      case Country.other:
        return "Other";
    }
  }

  String get flag {
    switch (this) {
      case Country.india:
        return "🇮🇳";
      case Country.china:
        return "🇨🇳";
      case Country.unitedStates:
        return "🇺🇸";
      case Country.unitedKingdom:
        return "🇬🇧";
      case Country.canada:
        return "🇨🇦";
      case Country.australia:
        return "🇦🇺";
      case Country.germany:
        return "🇩🇪";
      case Country.france:
        return "🇫🇷";
      case Country.japan:
        return "🇯🇵";
      case Country.singapore:
        return "🇸🇬";
      case Country.unitedArabEmirates:
        return "🇦🇪";
      case Country.other:
        return "🌍";
    }
  }
}
