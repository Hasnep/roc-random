## ## PCG algorithms, constants, and wrappers
##
## For more information about PCG see [www.pcg-random.org](https://www.pcg-random.org)
##
## > PCG is a family of simple fast space-efficient statistically good algorithms for random number generation.
##
module [
    Generation,
    Generator,
    State,
    seed,
    seed_variant,
    step,
    next,
    static,
    map,
    chain,
    list,
    u8,
    bounded_u8,
    i8,
    bounded_i8,
    u16,
    bounded_u16,
    i16,
    bounded_i16,
    u32,
    bounded_u32,
    i32,
    bounded_i32,
]

# This implementation is based on this paper [PCG: A Family of Simple Fast Space-Efficient Statistically Good Algorithms for Random Number Generation](https://www.pcg-random.org/pdf/hmc-cs-2014-0905.pdf)
# and this C++ header: [pcg_variants.h](https://github.com/imneme/pcg-c/blob/master/include/pcg_variants.h).
#
# Original Roc implementation by [JanCVanB](https://github.com/JanCVanB), January 2022
#
# Abbreviations:
# - M = Multiplication (see section 6.3.4 on page 45 in the paper)
# - PCG = Permuted Congruential Generator
# - RXS = Random XorShift (see section 5.5.1 on page 36 in the paper)
# - XS = XorShift (see section 5.5 on page 34 in the paper)

## A generator that produces pseudorandom `value`s using the PCG algorithm.
##
## ```
## rgb_generator : Generator { red: U8, green: U8, blue: U8 }
## rgb_generator =
##     { Random.chain <-
##         red: Random.u8,
##         green: Random.u8,
##         blue: Random.u8,
##     }
## ```
Generator value : State -> Generation value

## A pseudorandom value, paired with its [Generator]'s output state.
##
## This is required to chain multiple calls together passing the updated state.
Generation value : { value : value, state : State }

## Internal state for Generators
State := { s : U32, c : AlgorithmConstants }

# only used internally
AlgorithmConstants : {
    permute_multiplier : U32,
    permute_random_xor_shift : U32,
    permute_random_xor_shift_increment : U32,
    permute_xor_shift : U32,
    update_increment : U32,
    update_multiplier : U32,
}

## Construct an initial "seed" [State] for [Generator]s
seed : U32 -> State
seed = |s| seed_variant(s, default_u32_update_increment)

## Construct a specific "variant" of a "seed" for more advanced use.
##
## A "seed" is an initial [State] for [Generator]s.
##
## A "variant" is a [State] that specifies a `c.updateIncrement` constant,
## to produce a sequence of internal `value`s that shares no consecutive pairs
## with other variants of the same [State].
##
## Odd numbers are recommended for the update increment,
## to double the repetition period of sequences (by hitting odd values).
seed_variant : U32, U32 -> State
seed_variant = |s, u_i|
    c = {
        permute_multiplier: default_u32_permute_multiplier,
        permute_random_xor_shift: default_u32_permute_random_xor_shift,
        permute_random_xor_shift_increment: default_u32_permute_random_xor_shift_increment,
        permute_xor_shift: default_u32_permute_xor_shift,
        update_increment: u_i,
        update_multiplier: default_u32_update_multiplier,
    }

    @State({ s, c })

## Generate a [Generation] from a state
step : State, Generator value -> Generation value
step = |s, g| g(s)

## Generate a new [Generation] from an old [Generation]'s state
next : Generation *, Generator value -> Generation value
next = |x, g| g(x.state)

## Create a [Generator] that always returns the same thing.
static : value -> Generator value
static = |value|
    |state| { value, state }

## Map over the value of a [Generator].
map : Generator a, (a -> b) -> Generator b
map = |generator, mapper|
    |state|
        { value, state: state2 } = generator(state)

        { value: mapper(value), state: state2 }

## Compose two [Generator]s into a single [Generator].
##
## This works well with record builders:
##
## ```
## date_generator =
##     { Random.chain <-
##         year: Random.int(1, 2500),
##         month: Random.int(1, 12),
##         day: Random.int(1, 31),
##     }
## ```
chain : Generator a, Generator b, (a, b -> c) -> Generator c
chain = |first_generator, second_generator, combiner|
    |state|
        { value: first, state: state2 } = first_generator(state)
        { value: second, state: state3 } = second_generator(state2)

        { value: combiner(first, second), state: state3 }

expect
    always_five = static(5)

    List.range({ start: At(0), end: Before(100) })
    |> List.all(
        |seed_num|
            value =
                seed(seed_num)
                |> step(always_five)
                |> .value

            value == 5,
    )

expect
    doubled_int = bounded_i32(-100, 100) |> map(|i| i * 2)

    List.range({ start: At(0), end: Before(100) })
    |> List.all(
        |seed_num|
            next_seed = seed(seed_num)
            rand_int = step(next_seed, bounded_i32(-100, 100)) |> .value
            doubled_rand_int = step(next_seed, doubled_int) |> .value

            rand_int * 2 == doubled_rand_int,
    )

expect
    color_component_gen = bounded_i32(0, 255)
    rgb_generator =
        { chain <-
            r: color_component_gen,
            g: color_component_gen,
            b: color_component_gen,
        }

    next_seed = seed(123)
    rand_rgb = step(next_seed, rgb_generator) |> .value

    rand_rgb == { r: 65, g: 156, b: 137 }

## Generate a list of random values.
## ```
## generate_10_random_u8s : Generator (List U8)
## generate_10_random_u8s =
##     Random.list(Random.u8, 10)
## ```
list : Generator a, Int * -> Generator (List a)
list = |generator, length|
    |initial_state|
        List.range({ start: At(0), end: Before(length) })
        |> List.walk(
            { state: initial_state, value: [] },
            |prev, _|
                { value, state } = Random.step(prev.state, generator)
                { state, value: List.append(prev.value, value) },
        )

## Construct a [Generator] for 8-bit unsigned integers
u8 : Generator U8
u8 = between_unsigned(Num.min_u8, Num.max_u8) |> map(Num.int_cast)

## Construct a [Generator] for 8-bit unsigned integers between two boundaries (inclusive)
bounded_u8 : U8, U8 -> Generator U8
bounded_u8 = |x, y| between_unsigned(x, y) |> map(Num.int_cast)

## Construct a [Generator] for 8-bit signed integers
i8 : Generator I8
i8 =
    (minimum, maximum) = (Num.min_i8, Num.max_i8)
    # TODO: Remove these `I64` dependencies.
    range = (Num.to_i64(maximum)) - (Num.to_i64(minimum)) + 1
    |state|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        offset = permute(state) |> map_to_i32 |> Num.to_i64 |> Num.sub(Num.to_i64(Num.min_i8)) |> Num.rem(range)
        value = minimum |> Num.to_i64 |> Num.add(offset) |> Num.to_i8
        { value, state: update(state) }

## Construct a [Generator] for 8-bit signed integers between two boundaries (inclusive)
bounded_i8 : I8, I8 -> Generator I8
bounded_i8 = |x, y|
    (minimum, maximum) = sort(x, y)
    # TODO: Remove these `I64` dependencies.
    range = (Num.to_i64(maximum)) - (Num.to_i64(minimum)) + 1
    |state|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        offset = permute(state) |> map_to_i32 |> Num.to_i64 |> Num.sub(Num.to_i64(Num.min_i8)) |> Num.rem(range)
        value = minimum |> Num.to_i64 |> Num.add(offset) |> Num.to_i8
        { value, state: update(state) }

## Construct a [Generator] for 16-bit unsigned integers
u16 : Generator U16
u16 = between_unsigned(Num.min_u16, Num.max_u16) |> map(Num.int_cast)

## Construct a [Generator] for 16-bit unsigned integers between two boundaries (inclusive)
bounded_u16 : U16, U16 -> Generator U16
bounded_u16 = |x, y| between_unsigned(x, y) |> map(Num.int_cast)

## Construct a [Generator] for 16-bit signed integers
i16 : Generator I16
i16 =
    (minimum, maximum) = (Num.min_i16, Num.max_i16)
    # TODO: Remove these `I64` dependencies.
    range = (Num.to_i64(maximum)) - (Num.to_i64(minimum)) + 1
    |state|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        offset = permute(state) |> map_to_i32 |> Num.to_i64 |> Num.sub(Num.to_i64(Num.min_i16)) |> Num.rem(range)
        value = minimum |> Num.to_i64 |> Num.add(offset) |> Num.to_i16
        { value, state: update(state) }

## Construct a [Generator] for 16-bit signed integers between two boundaries (inclusive)
bounded_i16 : I16, I16 -> Generator I16
bounded_i16 = |x, y|
    (minimum, maximum) = sort(x, y)
    # TODO: Remove these `I64` dependencies.
    range = (Num.to_i64(maximum)) - (Num.to_i64(minimum)) + 1
    |state|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        offset = permute(state) |> map_to_i32 |> Num.to_i64 |> Num.sub(Num.to_i64(Num.min_i16)) |> Num.rem(range)
        value = minimum |> Num.to_i64 |> Num.add(offset) |> Num.to_i16
        { value, state: update(state) }

## Construct a [Generator] for 32-bit unsigned integers
u32 : Generator U32
u32 = between_unsigned(Num.min_u32, Num.max_u32)

## Construct a [Generator] for 32-bit unsigned integers between two boundaries (inclusive)
bounded_u32 : U32, U32 -> Generator U32
bounded_u32 = |x, y| between_unsigned(x, y)

## Construct a [Generator] for 32-bit signed integers
i32 : Generator I32
i32 =
    (minimum, maximum) = (Num.min_i32, Num.max_i32)
    # TODO: Remove these `I64` dependencies.
    range = (Num.to_i64(maximum)) - (Num.to_i64(minimum)) + 1
    |state|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        offset = permute(state) |> map_to_i32 |> Num.to_i64 |> Num.sub(Num.to_i64(Num.min_i32)) |> Num.rem(range)
        value = minimum |> Num.to_i64 |> Num.add(offset) |> Num.to_i32
        { value, state: update(state) }

## Construct a [Generator] for 32-bit signed integers between two boundaries (inclusive)
bounded_i32 : I32, I32 -> Generator I32
bounded_i32 = |x, y|
    (minimum, maximum) = sort(x, y)
    # TODO: Remove these `I64` dependencies.
    range = (Num.to_i64(maximum)) - (Num.to_i64(minimum)) + 1
    |state|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        offset = permute(state) |> map_to_i32 |> Num.to_i64 |> Num.sub(Num.to_i64(Num.min_i32)) |> Num.rem(range)
        value = minimum |> Num.to_i64 |> Num.add(offset) |> Num.to_i32
        { value, state: update(state) }

# Helpers for the above constructors -------------------------------------------
between_unsigned : Int a, Int a -> Generator (Int a)
between_unsigned = |x, y|
    (minimum, maximum) = sort(x, y)
    range = maximum - minimum |> Num.add_checked(1)

    |s|
        # TODO: Analyze this. The mod-ing might be biased towards a smaller offset!
        value =
            when range is
                Ok(r) -> minimum + (Num.int_cast(permute(s))) % r
                Err(_) -> permute(s) |> Num.int_cast
        state = update(s)

        { value, state }

map_to_i32 : U32 -> I32
map_to_i32 = |x|
    middle = Num.to_u32(Num.max_i32)
    if x <= middle then
        Num.min_i32 + Num.to_i32(x)
    else
        Num.to_i32((x - middle - 1))

sort = |x, y|
    if x < y then
        (x, y)
    else
        (y, x)

# See `RXS M XS` constants (line 168?)
# and `_DEFAULT_` constants (line 276?)
# in the PCG C++ header (see link above).
default_u32_permute_multiplier = 277_803_737
default_u32_permute_random_xor_shift = 28
default_u32_permute_random_xor_shift_increment = 4
default_u32_permute_xor_shift = 22
default_u32_update_increment = 2_891_336_453
default_u32_update_multiplier = 747_796_405

# See `pcg_output_rxs_m_xs_8_8` (on line 170?) in the PCG C++ header (see link above).
permute : State -> U32
permute = |@State({ s, c })|
    pcg_rxs_m_xs(s, c.permute_random_xor_shift, c.permute_random_xor_shift_increment, c.permute_multiplier, c.permute_xor_shift)

# See section 6.3.4 on page 45 in the PCG paper (see link above).
pcg_rxs_m_xs : U32, U32, U32, U32, U32 -> U32
pcg_rxs_m_xs = |state, random_xor_shift, random_xor_shift_increment, multiplier, xor_shift|

    inner =
        random_xor_shift
        |> Num.shift_right_zf_by(Num.int_cast(state))
        |> Num.add_wrap(random_xor_shift_increment)
        |> Num.shift_right_zf_by(Num.int_cast(state))

    partial =
        state
        |> Num.bitwise_xor(inner)
        |> Num.mul_wrap(multiplier)

    Num.bitwise_xor(partial, Num.shift_right_zf_by(xor_shift, Num.int_cast(partial)))

# See section 4.1 on page 20 in the PCG paper (see link above).
pcg_step : U32, U32, U32 -> U32
pcg_step = |state, multiplier, increment|
    state
    |> Num.mul_wrap(multiplier)
    |> Num.add_wrap(increment)

# See `pcg_oneseq_8_step_r` (line 409?) in the PCG C++ header (see link above).
update : State -> State
update = |@State({ s, c })|

    s_new : U32
    s_new = pcg_step(s, c.update_multiplier, c.update_increment)

    @State({ s: s_new, c })

# Test U8 generation
# TODO confirm this is the right value for this seed
expect
    test_generator = u8
    test_seed = seed(123)
    actual = test_generator(test_seed)
    expected = 65u8
    actual.value == expected

# Test U16 generation
# TODO confirm this is the right value for this seed
expect
    test_generator = bounded_u16(0, 250)
    test_seed = seed(123)
    actual = test_generator(test_seed)
    expected = 182u16
    actual.value == expected

# Test U32 generation
# TODO confirm this is the right value for this seed
expect
    test_generator = bounded_u32(0, 250)
    test_seed = seed(123)
    actual = test_generator(test_seed)
    expected = 143u32
    actual.value == expected

# Test I8 generation
# TODO confirm this is the right value for this seed
expect
    test_generator = bounded_i8(0, 9)
    test_seed = seed(6)
    actual = test_generator(test_seed)
    expected = -8i8
    actual.value == expected

# Test I16 generation
# TODO confirm this is the right value for this seed
expect
    test_generator = bounded_i16(0, 9)
    test_seed = seed(6)
    actual = test_generator(test_seed)
    expected = -8i16
    actual.value == expected

# Test I32 generation
# TODO confirm this is the right value for this seed
expect
    test_generator = bounded_i32(10, 9)
    test_seed = seed(6)
    actual = test_generator(test_seed)
    expected = 9i32
    actual.value == expected
