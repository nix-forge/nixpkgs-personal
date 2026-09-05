import Darwin
import Foundation

final class CaptureSessionLock {
  private let descriptor: Int32

  private init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }

  static func acquire() throws -> CaptureSessionLock? {
    let filename = "dev.ianmh.ocr-capture-\(geteuid()).lock"
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
    #if compiler(>=6.2)
      // Darwin temporarily borrows the string's NUL-terminated storage.
      let descriptor = unsafe open(
        path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    #else
      let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    #endif
    guard descriptor >= 0 else {
      throw OCRCaptureError.captureUnavailable("could not create the per-user session lock")
    }

    var information = stat()
    #if compiler(>=6.2)
      // fstat initializes the in-scope value and does not retain its pointer.
      let status = unsafe fstat(descriptor, &information)
    #else
      let status = fstat(descriptor, &information)
    #endif
    guard status == 0,
      information.st_uid == geteuid(),
      information.st_mode & S_IFMT == S_IFREG
    else {
      close(descriptor)
      throw OCRCaptureError.captureUnavailable(
        "the per-user session lock is not a private regular file")
    }

    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let lockError = errno
      close(descriptor)
      if lockError == EWOULDBLOCK { return nil }
      throw OCRCaptureError.captureUnavailable("could not acquire the per-user session lock")
    }
    return CaptureSessionLock(descriptor: descriptor)
  }
}
