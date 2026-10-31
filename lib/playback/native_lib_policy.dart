abstract final class NativeLibPolicy {
  static const minimumFfmpegRelease = (7, 1);
  static const minimumFfmpegGitRevision = 117622;

  // Temporary: media-kit's newest macOS libmpv (libmpv-darwin-build v0.7.3)
  // still ships FFmpeg 6.0. Restore minimumFfmpegRelease once it moves on.
  static const macosMinimumFfmpegRelease = (6, 0);

  static bool acceptsFfmpeg(String? version, {required String os}) {
    if (os == 'linux') return true;
    final value = version?.trim() ?? '';
    final git = RegExp(r'^N-(\d+)-g[0-9a-f]+').firstMatch(value);
    if (git != null) {
      return int.parse(git.group(1)!) >= minimumFfmpegGitRevision;
    }
    final release = RegExp(r'^n?(\d+)\.(\d+)').firstMatch(value);
    if (release == null) return false;
    final major = int.parse(release.group(1)!);
    final minor = int.parse(release.group(2)!);
    final (minMajor, minMinor) = os == 'macos'
        ? macosMinimumFfmpegRelease
        : minimumFfmpegRelease;
    return major > minMajor || (major == minMajor && minor >= minMinor);
  }
}
