import "dart:io";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/home/data/enums/current_page.dart";
import "package:stera/src/modules/home/providers/navigation_provider.dart";
import "package:stera/src/modules/home/ui/widgets/nav_item.dart";
import "package:stera/src/modules/home/ui/widgets/notification_permission_bottomsheet.dart";
import "package:stera/src/modules/upload/providers/managers/upload_queue_manager.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:stera/src/modules/demo/providers/demo_video_preload_provider.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:stera/src/services/permission_service/permission_service.dart";
import "package:flutter/material.dart";
import "package:permission_handler/permission_handler.dart";
import "package:provider/provider.dart";
import "package:solar_icons/solar_icons.dart";

class NavigationPage extends StatefulWidget {
  static const String routeName = "/root";

  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage>
    with WidgetsBindingObserver {
  bool _isShowingPermissionSheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<DemoVideoPreloadProvider>().warmBundle();
      checkAndRequestNotificationPermission();
      getVideoLists();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isShowingPermissionSheet) {
      _recheckPermissionAfterSettings();
    }
  }

  void _processUploadQueue() {
    final error = UploadQueueManager.instance.processQueue();

    if (error != null) {
      AppToast.show(title: error.message, appToastType: AppToastType.error);
    }
  }

  void _showNotificationPermissionBottomSheet() {
    if (_isShowingPermissionSheet) return;

    _isShowingPermissionSheet = true;
    showModalBottomSheet(
      context: context,
      isDismissible: Platform.isIOS,
      enableDrag: Platform.isIOS,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationPermissionBottomSheet(
        onDismiss: Platform.isIOS
            ? () {
                _isShowingPermissionSheet = false;
              }
            : null,
      ),
    ).then((_) {
      // Handle dismissal callback
      if (Platform.isIOS && _isShowingPermissionSheet) {
        _isShowingPermissionSheet = false;
      }
    });
  }

  Future<void> _recheckPermissionAfterSettings() async {
    final status = await PermissionService.getNotificationPermissionStatus();

    if (status.isGranted && _isShowingPermissionSheet) {
      _isShowingPermissionSheet = false;
      AppRouter.pop();
      _processUploadQueue();
    }
  }

  void checkAndRequestNotificationPermission() async {
    final status = await PermissionService.getNotificationPermissionStatus();

    if (status.isGranted) {
      // Permission granted, process queue
      _processUploadQueue();
      return;
    }

    if (status.isDenied) {
      // First time - request permission
      final result = await Permission.notification.request();
      if (result.isGranted) {
        _processUploadQueue();
        return;
      }
    }

    // Permission denied or permanently denied - show bottom sheet
    // On iOS, check if user has skipped before
    if (Platform.isIOS) {
      final hasSkipped =
          KvStore.get<bool>(
            KvStoreKeys.notificationPermissionSkipped,
            defaultValue: false,
          ) ??
          false;
      if (hasSkipped) {
        // User has skipped before, don't show bottom sheet
        return;
      }
    }

    // Show bottom sheet (Android always shows, iOS shows if not skipped)
    _showNotificationPermissionBottomSheet();
  }

  void getVideoLists() async {
    final ap = context.read<AuthProvider>();
    if (ap.user == null) return;
    final upv = context.read<UploadedVideosProvider>();
    final error = await upv.getUploadedVideos();
    if (error != null) {
      AppToast.show(title: error.message, appToastType: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final currentIndex = nav.currentIndex;

    return PopScope(
      canPop: nav.currentPage == CurrentPage.home,
      onPopInvokedWithResult: (didPop, result) {
        final np = context.read<NavigationProvider>();

        if (!didPop && np.currentPage != CurrentPage.home) {
          np.setCurrentPage(CurrentPage.home);
        }
      },
      child: Scaffold(
        body: nav.pages[currentIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceSecondary,
            border: Border(
              top: BorderSide(color: context.colors.borderDivider, width: 1),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: NavItem(
                      iconPath: CurrentPage.home.iconPath,
                      label: CurrentPage.home.label,
                      isActive: nav.currentPage == CurrentPage.home,
                      onTap: () => nav.setCurrentPage(CurrentPage.home),
                    ),
                  ),
                  Pressable(
                    pressedScale: 0.9,
                    onTap: () => nav.setCurrentPage(CurrentPage.addUpload),
                    child: Container(
                      width: 60,
                      height: 47,
                      decoration: BoxDecoration(
                        color: nav.currentPage == CurrentPage.addUpload
                            ? context.colors.textPrimary
                            : context.colors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Icon(
                          SolarIconsOutline.uploadSquare,
                          size: 24,
                          color: nav.currentPage == CurrentPage.addUpload
                              ? context.colors.textInversePrimary
                              : context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: NavItem(
                      iconPath: CurrentPage.upload.iconPath,
                      label: CurrentPage.upload.label,
                      isActive: nav.currentPage == CurrentPage.upload,
                      onTap: () => nav.setCurrentPage(CurrentPage.upload),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
