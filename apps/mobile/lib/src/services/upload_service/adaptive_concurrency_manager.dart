import "dart:math";
import "dart:developer" as dev;

/// Adaptive concurrency manager using AIMD algorithm
/// (Additive Increase / Multiplicative Decrease)
///
/// This class dynamically adjusts the number of concurrent chunk uploads
/// based on network conditions and upload success/failure rates.
///
/// Algorithm:
/// - Starts conservatively with 1 concurrent upload
/// - Increases concurrency by 1 when performance is good (additive increase)
/// - Decreases concurrency by 1 on failure, or halves on consecutive failures (multiplicative decrease)
/// - Uses sliding window of recent results to detect network conditions
class AdaptiveConcurrencyManager {
  // Configuration
  final int minConcurrency;
  final int maxConcurrency;
  final int targetUploadTimeMs;

  // Current state
  int _currentConcurrency;

  // Metrics tracking
  final List<bool> _recentResults = []; // true=success, false=fail
  final int _maxRecentResults = 10; // Sliding window size

  final List<int> _recentUploadTimes = []; // milliseconds
  int _consecutiveFailures = 0;
  int _totalChunksProcessed = 0;

  AdaptiveConcurrencyManager({
    this.minConcurrency = 1,
    this.maxConcurrency = 10,
    // 40 s for a 30 MB chunk assumes ~6 Mbps effective per-chunk throughput;
    // slower links trigger the concurrency decrease branch.
    this.targetUploadTimeMs = 40000,
    int initialConcurrency = 1,
  }) : _currentConcurrency = initialConcurrency;

  /// Called after each chunk completes
  ///
  /// [success] - whether the chunk upload succeeded
  /// [durationMs] - how long the upload took in milliseconds
  void onChunkComplete(bool success, int durationMs) {
    _totalChunksProcessed++;

    // Update metrics
    _updateMetrics(success, durationMs);

    // Adjust concurrency
    _adjustConcurrency();

    // Periodic deep evaluation
    if (_totalChunksProcessed % 5 == 0) {
      _periodicEvaluation();
    }
  }

  void _updateMetrics(bool success, int durationMs) {
    // Track success/failure
    _recentResults.add(success);
    if (_recentResults.length > _maxRecentResults) {
      _recentResults.removeAt(0); // Keep last 10 only
    }

    // Track upload times
    if (success) {
      _recentUploadTimes.add(durationMs);
      if (_recentUploadTimes.length > _maxRecentResults) {
        _recentUploadTimes.removeAt(0);
      }
    }

    // Track consecutive failures
    if (success) {
      _consecutiveFailures = 0;
    } else {
      _consecutiveFailures++;
    }
  }

  void _adjustConcurrency() {
    if (_recentResults.isEmpty) return;

    final successRate = _calculateSuccessRate();
    final recentAvgTime = _calculateAvgUploadTime(
      lastN: 3,
    ); // Last 3 chunks for current conditions
    final overallAvgTime =
        _calculateAvgUploadTime(); // All chunks for conservative increase
    final oldConcurrency = _currentConcurrency;

    if (_recentResults.last == true) {
      // Last chunk succeeded
      // Check if RECENT upload times are too high (network congestion)
      // Use last 3 chunks to detect current network conditions
      if (recentAvgTime > targetUploadTimeMs * 1.5 &&
          _recentUploadTimes.length >= 3) {
        // Recent uploads are 50% higher than target - reduce concurrency
        _currentConcurrency = max(_currentConcurrency - 1, minConcurrency);
        if (_currentConcurrency != oldConcurrency) {
          dev.log(
            "⏱️ Decreasing concurrency: $oldConcurrency → $_currentConcurrency (slow uploads: recent avg ${recentAvgTime}ms > target ${targetUploadTimeMs}ms)",
          );
        }
      } else if (successRate >= 0.85 && overallAvgTime < targetUploadTimeMs) {
        // Good OVERALL performance - Additive increase (conservative)
        // Requires sustained good performance across all tracked chunks
        _currentConcurrency = min(_currentConcurrency + 1, maxConcurrency);
        if (_currentConcurrency != oldConcurrency) {
          dev.log(
            "⏱️ Increasing concurrency: $oldConcurrency → $_currentConcurrency (success rate: ${(successRate * 100).toStringAsFixed(1)}%, overall avg: ${overallAvgTime}ms)",
          );
        }
      }
    } else {
      // Last chunk failed - Multiplicative decrease
      if (_consecutiveFailures >= 3) {
        _currentConcurrency = max(_currentConcurrency ~/ 2, minConcurrency);
        dev.log(
          "⏱️ Halving concurrency: $oldConcurrency → $_currentConcurrency (consecutive failures: $_consecutiveFailures)",
        );
      } else {
        _currentConcurrency = max(_currentConcurrency - 1, minConcurrency);
        if (_currentConcurrency != oldConcurrency) {
          dev.log(
            "⏱️ Decreasing concurrency: $oldConcurrency → $_currentConcurrency (failure detected)",
          );
        }
      }
    }
  }

  void _periodicEvaluation() {
    final successRate = _calculateSuccessRate();

    // Emergency mode: Network is very bad
    if (successRate < 0.60) {
      _currentConcurrency = minConcurrency;
      dev.log(
        "⏱️ 🚨 Emergency mode: Dropping to min concurrency ($minConcurrency) - success rate: ${(successRate * 100).toStringAsFixed(1)}%",
      );
    }
    // Note: Removed "bonus increase" to prevent concurrency from ramping up too fast
  }

  double _calculateSuccessRate() {
    if (_recentResults.isEmpty) return 1.0;
    final successes = _recentResults.where((r) => r == true).length;
    return successes / _recentResults.length;
  }

  int _calculateAvgUploadTime({int? lastN}) {
    if (_recentUploadTimes.isEmpty) return 0;

    // If lastN is specified, only use the last N entries
    final timesToUse = lastN != null && _recentUploadTimes.length > lastN
        ? _recentUploadTimes.sublist(_recentUploadTimes.length - lastN)
        : _recentUploadTimes;

    if (timesToUse.isEmpty) return 0;
    final sum = timesToUse.reduce((a, b) => a + b);
    return sum ~/ timesToUse.length;
  }

  /// Get the current recommended concurrency level
  int get concurrency => _currentConcurrency;

  /// Get current statistics as a formatted string
  String getStats() {
    final successRate = _calculateSuccessRate();
    final recentAvgTime = _calculateAvgUploadTime(lastN: 3);
    final overallAvgTime = _calculateAvgUploadTime();
    return "⏱️ Concurrency: $_currentConcurrency | Success: ${(successRate * 100).toStringAsFixed(1)}% | Recent avg: ${recentAvgTime}ms | Overall avg: ${overallAvgTime}ms | Processed: $_totalChunksProcessed chunks";
  }

  /// Reset all metrics and concurrency to initial state.
  /// [initialConcurrency] overrides the starting concurrency level.
  void reset({int? initialConcurrency}) {
    _currentConcurrency = initialConcurrency ?? minConcurrency;
    _recentResults.clear();
    _recentUploadTimes.clear();
    _consecutiveFailures = 0;
    _totalChunksProcessed = 0;
  }
}
