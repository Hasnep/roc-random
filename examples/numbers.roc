app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.15.0/SlwdbJ-3GR7uBWQo6zlmYWNYOxnvo8r6YABXD-45UOw.tar.br",
    rand: "../package/main.roc",
}

import cli.Stdout
import rand.Random

# Print a list of 10 random numbers in the range 25-75 inclusive.
main =
    randomNumbers
    |> List.map Num.toStr
    |> Str.joinWith "\n"
    |> \numbersListStr -> Stdout.line "$(numbersListStr)"

numbersGenerator : Random.Generator (List U32)
numbersGenerator =
    Random.list (Random.boundedU32 25 75) 10

randomNumbers : List U32
randomNumbers =
    { value: numbers } = Random.step (Random.seed 1234) numbersGenerator

    numbers

expect
    actual = randomNumbers
    actual == [52, 34, 26, 69, 34, 35, 51, 74, 70, 39]
