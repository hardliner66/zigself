"
Copyright (c) 2022, sin-ack <sin-ack@protonmail.com>

SPDX-License-Identifier: GPL-3.0-only
"

std _AddSlots: (|
    testing = (|
        "The base object for a test. Provides assertion functions for tests."
        test = (|
            parent* = std traits singleton.

            "Expects the expected value to be identical to the actual value."
            expect: actual ToBeIdenticalTo: expected = (
                (expected == actual) ifFalse: [
                    'Expected: ' print. expected _Inspect. '' printLine.
                    'Actual: ' print. actual _Inspect. '' printLine.
                    _Error: 'Expected identical values'
                ].
            ).

            "Expects the expected value to NOT be identical to the actual value."
            expect: actual ToNotBeIdenticalTo: expected = (
                (expected == actual) ifTrue: [
                    _Error: 'Expected non-identical values'
                ].
            ).

            "Expects the expected value to be equal to the actual value."
            expect: actual ToBe: expected = (
                (expected = actual) ifFalse: [
                    'Expected: ' print. expected _Inspect. '' printLine.
                    'Actual: ' print. actual _Inspect. '' printLine.
                    _Error: 'Expected equal values'
                ].
            ).

            "Expects the expected value to NOT be equal to the actual value."
            expect: actual ToNotBe: expected = (
                (expected = actual) ifTrue: [
                    'Expected: ' print. expected _Inspect. '' printLine.
                    'Actual: ' print. actual _Inspect. '' printLine.
                    _Error: 'Expected unequal values'
                ].
            ).

            "Passes a block that takes a single argument to blk, and expects it
             to not be called."
            expectToNotFail: blk = (
                blk value: [| :err | _Error: 'Unexpected failure' ]
            ).

            "Passes a block that takes a single argument to blk, and expects it
             to be called."
            expectToFail: blk = (
                blk value: [| :err | ^ nil ].
                _Error: 'Expected failure block to be called'.
            ).
        |).
    |).
|).
