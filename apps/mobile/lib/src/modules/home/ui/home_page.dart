import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/common/widgets/app_header.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/demo/providers/demo_video_preload_provider.dart";
import "package:stera/src/modules/demo/ui/widgets/app_demo_video_inline_intro_card.dart";
import "package:stera/src/core/common/widgets/open_source_badge.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:stera/src/modules/home/ui/widgets/upload_progress_card.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class HomePage extends StatefulWidget {
  static const String routeName = "/home";
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ap = context.read<AuthProvider>();
      final upv = context.read<UploadedVideosProvider>();

      if (ap.user == null) return;

      context
          .read<DemoVideoPreloadProvider>()
          .obtainFullscreenController()
          .then((_) {}, onError: (_) {});

      if (upv.videos.isEmpty) {
        final err = await upv.getUploadedVideos();
        if (err != null) {
          AppToast.show(title: err.message);
        }
      }
    });
  }

  Future<void> _refreshData(BuildContext context) async {
    final ap = context.read<AuthProvider>();
    final upv = context.read<UploadedVideosProvider>();

    if (ap.user == null) return;

    final hpError = await upv.refresh();

    if (hpError != null) {
      AppToast.show(title: hpError.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.w,
      height: context.h,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(AppAssets.texture),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            context.colors.surfacePrimary,
            BlendMode.modulate,
          ),
        ),
      ),
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppHeader(
            text1: "Stera",
            text2: " by FPV Labs",
            customStyle2: context.textTheme.head3XlHandjet.copyWith(
              fontWeight: AppType.bold,
              fontSize: AppType.xl3Plus,
            ),
            actions: const [
              Center(
                child: Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: OpenSourceBadge(),
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            backgroundColor: context.colors.surfacePrimary,
            color: context.colors.textPrimary,
            onRefresh: () => _refreshData(context),
            child: const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.huge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppDemoVideoInlineIntroCard(),
                  SizedBox(height: AppSpacing.lg),
                  UploadProgressCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
