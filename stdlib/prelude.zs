import { Option } from "./Option.zs"
import { Either } from "./Either.zs"
import { List, newList } from "./arraylist.zs"
export { String, plus } from "./string.zs"

scalar number
scalar long
scalar short
scalar byte
scalar boolean
scalar char

struct Pointer<T> {
    ptr: long
}

external fn loadLibrary(path: String): void

external fn ptr<T>(value: T): Pointer<T>
external fn deref<T>(ptr: Pointer<T>): T

export fn print(s: String): void {
  let total = s.len + 1
  let buf: Pointer<char> = alloc(total)
  for (let i = 0; i < s.len; i = i + 1) {
    buf[i] = charAt(s, i)
  }
  buf[s.len] = '\n'
  asm {
    in rax = 1
    in rdi = 1
    in rsi = buf
    in rdx = total
    "syscall"
  }
  free(buf, total)
}

export fn numberToString(n: number): String {
  let buf = ['\0'; 20]
  let pos = 19
  let is_neg = 0
  let val = n

  if (n < 0) {
    is_neg = 1
    val = 0 - n
  }

  if (val == 0) {
    buf[pos] = 48
    pos = pos - 1
  }

  while (val > 0) {
    let digit = val % 10
    buf[pos] = digit + 48
    pos = pos - 1
    val = val / 10
  }

  if (is_neg == 1) {
    buf[pos] = 45
    pos = pos - 1
  }

  let start = pos + 1
  let len = 20 - start
  let result: Pointer<char> = alloc(len)
  for (let i = 0; i < len; i = i + 1) {
    result[i] = buf[start + i]
  }
  return String { len: len, data: result }
}

export fn print(n: number): void {
  let s = numberToString(n)
  print(s)
  free(s.data, s.len)
}
export fn alloc(size: long): Pointer<char> {
  asm {
    in rax = 9
    in rdi = 0
    in rsi = size
    in rdx = 3
    in r10 = 34
    in r8 = -1
    in r9 = 0
    out rax = addr
    "syscall"
  }
  return addr
}

export fn free(addr: long, size: long): void {
  asm {
    in rax = 11
    in rdi = addr
    in rsi = size
    "syscall"
  }
}

export fn readLine(): String {
  let buf = ['\0'; 1024]

  asm {
    in rax = 0
    in rdi = 0
    in rsi = ptr(buf)
    in rdx = 1024
    out rax = bytes
    "syscall"
  }
  if (bytes > 0) {
    if (buf[bytes - 1] == 10) {
      bytes = bytes - 1
    }
  }

  return String { len: bytes, data: ptr(buf) }
}

export fn charAt(s: String, i: number): char = s.data[i]

export fn toCstr(s: String): Pointer<char> {
  let buf: Pointer<char> = alloc(s.len + 1)
  for (let i = 0; i < s.len; i = i + 1) {
    buf[i] = charAt(s, i)
  }
  buf[s.len] = '\0'
  return buf
}

export fn strEq(a: String, b: String): boolean {
  if (a.len != b.len) return false
  for (let i = 0; i < a.len; i = i + 1) {
    if (charAt(a, i) != charAt(b, i)) return false
  }
  return true
}

export fn strConcat(a: String, b: String): String {
  let total = a.len + b.len
  let buf = alloc(total)
  for (let i = 0; i < a.len; i = i + 1) {
    buf[i] = charAt(a, i)
  }
  for (let i = 0; i < b.len; i = i + 1) {
    buf[a.len + i] = charAt(b, i)
  }
  return String { len: total, data: buf }
}

export fn substr(s: String, start: number, length: number): String {
  let buf = alloc(length)
  for (let i = 0; i < length; i = i + 1) {
    buf[i] = charAt(s, start + i)
  }
  return String { len: length, data: buf }
}
