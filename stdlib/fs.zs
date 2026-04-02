import { String, toCstr, alloc, free, charAt } from "./prelude.zs"
import { Either } from "./Either.zs"

export const O_RDONLY = 0
export const O_WRONLY = 1
export const O_RDWR   = 2
export const O_CREAT  = 64
export const O_TRUNC  = 512
export const O_APPEND = 1024

export const O_WRITE_NEW    = 577
export const O_WRITE_APPEND = 1025
export const O_WRITE_CREATE = 65

export const MODE_DEFAULT = 420

export enum FsError {
  NotFound,
  PermissionDenied,
  BadFd,
  NoSpace,
  IoError,
}

fn errnoToFsError(errno: number): FsError = match errno {
  2  -> FsError.NotFound,
  9  -> FsError.BadFd,
  13 -> FsError.PermissionDenied,
  28 -> FsError.NoSpace,
  else -> FsError.IoError
}

export fn open(path: String, flags: number, mode: number): Either<FsError, number> {
  let cpath = toCstr(path)
  asm {
    in rax = 2
    in rdi = cpath
    in rsi = flags
    in rdx = mode
    out rax = fd
    "syscall"
  }
  free(cpath, path.len + 1)
  if (fd < 0) {
    return Either.Left(errnoToFsError(0 - fd))
  }
  return Either.Right(fd)
}

export fn close(fd: number): void {
  asm {
    in rax = 3
    in rdi = fd
    "syscall"
  }
}

export fn writeFd(fd: number, s: String): number {
  asm {
    in rax = 1
    in rdi = fd
    in rsi = s.data
    in rdx = s.len
    out rax = result
    "syscall"
  }
  return result
}

export fn readFd(fd: number, buf: Pointer<char>, count: number): number {
  asm {
    in rax = 0
    in rdi = fd
    in rsi = buf
    in rdx = count
    out rax = result
    "syscall"
  }
  return result
}

export fn readFile(path: String): Either<FsError, String> {
  let fd = open(path, O_RDONLY, 0)!!
  let cap = 65536
  let buf: Pointer<char> = alloc(cap)
  let bytes = readFd(fd, buf, cap)
  close(fd)
  if (bytes < 0) {
    free(buf, cap)
    return Either.Left(errnoToFsError(0 - bytes))
  }
  return Either.Right(String { len: bytes, data: buf })
}

export fn writeFile(path: String, content: String): Either<FsError, number> {
  let fd = open(path, O_WRITE_NEW, MODE_DEFAULT)!!
  let written = writeFd(fd, content)
  close(fd)
  if (written < 0) {
    return Either.Left(errnoToFsError(0 - written))
  }
  return Either.Right(written)
}
