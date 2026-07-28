import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_file_tile/upload_file_tile.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:flutter/cupertino.dart";
import "package:provider/provider.dart";

class NotStartedVideosGridView extends StatelessWidget {
  const NotStartedVideosGridView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (_, up, _) {
        if (up.loading) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl).copyWith(top: 64),
              child: const CupertinoActivityIndicator(),
            ),
          );
        }

        if (up.picker.loading && up.allUploads.isEmpty) {
          return Container(
            alignment: Alignment.center,
            width: context.w,
            margin: const EdgeInsets.all(AppSpacing.xl),
            child: const CupertinoActivityIndicator(),
          );
        }

        final allUploads = up.allUploads
            .where(
              (u) =>
                  !u.isHidden &&
                  u.status == UploadStatus.notStarted &&
                  ((u.mimeType?.startsWith("video/") ?? false) ||
                      u.mimeType == "application/zip" ||
                      u.mimeType == "application/octet-stream"),
            )
            .toList();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: allUploads.length,
          itemBuilder: (context, index) {
            return UploadFileTile(uploadId: allUploads[index].id);
          },
        );
      },
    );
  }
}
