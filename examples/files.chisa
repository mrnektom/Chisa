import { readFile } from "../stdlib/fs.zs"

let result = readFile("./files.zs")

match result {
  Either.Right(content) -> print(content),
  Either.Left(err) -> print("error reading file")
}