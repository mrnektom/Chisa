import { print } from "prelude"

fn main(): void {
  let a = Option.Some(42)
  let b = Option.None
  print(a.getOrElse(0))
  print(b.getOrElse(0))
}
