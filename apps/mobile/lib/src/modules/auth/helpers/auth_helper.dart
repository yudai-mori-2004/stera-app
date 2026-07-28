import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/profile/providers/profile_provider.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:stera/src/modules/home/providers/navigation_provider.dart";
import "package:stera/src/modules/onboarding/providers/onboarding_provider.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:provider/provider.dart";

class AuthHelper {
  static Future<void> reset() async {
    final ctx = AppRouter.navigatorKey.currentContext;

    if (ctx != null) {
      final ap = ctx.read<AuthProvider>();
      final pp = ctx.read<ProfileProvider>();
      final uvp = ctx.read<UploadedVideosProvider>();
      final np = ctx.read<NavigationProvider>();
      final op = ctx.read<OnboardingProvider>();
      final up = ctx.read<UploadProvider>();

      ap.reset();
      pp.reset();
      uvp.reset();
      np.reset();
      op.reset();
      up.reset();
    }
  }
}
