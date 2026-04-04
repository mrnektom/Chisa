export enum Either<L, R> {
  Left(L),
  Right(R),
}

export fn Either<L, R>.mapRight<R2>(f: (R) -> R2): Either<L, R2> = match this {
  Either.Left(e)  -> Either.Left(e),
  Either.Right(v) -> Either.Right(f(v))
}

export fn Either<L, R>.getOrElse(default: R): R = match this {
  Either.Left(_)  -> default,
  Either.Right(v) -> v
}

export fn Either<L, R>.isOk(): boolean = match this {
  Either.Left(_)  -> false,
  Either.Right(_) -> true
}
