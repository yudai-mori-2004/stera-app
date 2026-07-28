import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/modules/upload/helpers/upload_utils.dart";
import "package:stera/src/modules/upload_estimate/helpers/upload_estimate_format.dart";
import "package:flutter/material.dart";

class UploadFileTileStatusBadge extends StatelessWidget {
  final int? filesize;

  /// Live time-remaining estimate; shown next to the file size while
  /// uploading.
  final Duration? eta;

  const UploadFileTileStatusBadge({super.key, this.filesize, this.eta});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            formatFileSize(filesize),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodyXs,
          ),
        ),
        if (eta != null)
          Flexible(
            child: Text(
              formatEtaShort(eta!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyXs.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
