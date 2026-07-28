enum MethodType { get, post, patch, put, delete }

extension MethodTypeX on MethodType {
  String get id {
    switch (this) {
      case MethodType.get:
        return "GET";
      case MethodType.post:
        return "POST";
      case MethodType.patch:
        return "PATCH";
      case MethodType.put:
        return "PUT";
      case MethodType.delete:
        return "DELETE";
    }
  }
}
