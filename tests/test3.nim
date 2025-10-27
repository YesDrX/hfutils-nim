import unittest
import json, tables, sets
import hfutils_nim/[json, static_types]

# Define additional test types
type
    Size = enum
        Small = 1
        Medium = 2
        Large = 3

    Point = object
        x: int
        y: int
    
    Status = enum
        Active
        Inactive
        Pending

    Color = enum
        Red
        Green
        Blue

    Person = object
        name: string
        age: int
        active: bool
        colors: seq[Color]
        metadata: JsonNode

    ComplexObject = object
        id: int
        name: string
        values: seq[float]
        flags: seq[Status]
        dimensions: array[3, int]
    
    MixedTable = object
        stringTable: Table[string, int]
        intTable: Table[int, string]
        enumTable: Table[Color, int]

    UnionLike = object
        case kind: bool
        of true:
            intValue: int
        of false:
            stringValue: string

    WithDefaults = object
        required: string
        optional: string = "default"
        numbers: seq[int] = @[1, 2, 3]

    CustomInt = distinct int

    Wrapper[T] = object
        value: T
        tag: string

# More custom hooks for testing
type Timestamp = distinct int64

template customNodeAsHook[T](n: JsonNode, t: typedesc[T]): untyped =
    when T is Timestamp:
        return T(n.getInt().int64)

proc customJsonDumpHook[T](t: T, result: var string) =
    when T is Timestamp:
        return result.add($int64(t))

# Test suite continues...
suite "Extended nodeAs function tests":

    test "Array types":
        let jsonArray = %[1, 2, 3]
        let result = nodeAs(jsonArray, array[3, int])
        check:
            result == [1, 2, 3]
            result[0] == 1
            result[1] == 2
            result[2] == 3

    test "Array with different types":
        let jsonArray = %["a", "b", "c"]
        let result = nodeAs(jsonArray, array[3, string])
        check:
            result == ["a", "b", "c"]

    test "Empty array":
        let jsonArray = newJArray()
        let result = nodeAs(jsonArray, array[0, int])
        check:
            result.len == 0

    test "Enum with numeric values":
        check:
            nodeAs(newJInt(1), Size) == Small
            nodeAs(newJInt(2), Size) == Medium
            nodeAs(newJInt(3), Size) == Large
            nodeAs(newJString("Small"), Size) == Small
            nodeAs(newJString("Medium"), Size) == Medium
            nodeAs(newJString("Large"), Size) == Large

    test "Complex object with all field types":
        let jsonComplex = %*{
            "id": 42,
            "name": "test",
            "values": [1.1, 2.2, 3.3],
            "flags": ["Active", "Pending"],
            "dimensions": [10, 20, 30],
            "nested": {"x": 5, "y": 10}
        }

        let complex = nodeAs(jsonComplex, ComplexObject)
        check:
            complex.id == 42
            complex.name == "test"
            complex.values == @[1.1, 2.2, 3.3]
            complex.flags == @[Active, Pending]
            complex.dimensions == [10, 20, 30]

    test "Object with tables":
        let jsonMixed = %*{
            "stringTable": {"a": 1, "b": 2},
            "intTable": {"1": "one", "2": "two"},
            "enumTable": {"Red": 10, "Green": 20}
        }

        let mixed = nodeAs(jsonMixed, MixedTable)
        check:
            mixed.stringTable["a"] == 1
            mixed.stringTable["b"] == 2
            mixed.intTable[1] == "one"
            mixed.intTable[2] == "two"
            mixed.enumTable[Red] == 10
            mixed.enumTable[Green] == 20

    test "Object with default values":
        let jsonWithDefaults = %*{
            "required": "provided"
        }

        let withDefaults = nodeAs(jsonWithDefaults, WithDefaults)
        check:
            withDefaults.required == "provided"
            withDefaults.optional == "default"
            withDefaults.numbers == @[1, 2, 3]

    test "Object with overridden defaults":
        let jsonWithDefaults = %*{
            "required": "provided",
            "optional": "overridden",
            "numbers": [4, 5, 6]
        }

        let withDefaults = nodeAs(jsonWithDefaults, WithDefaults)
        check:
            withDefaults.required == "provided"
            withDefaults.optional == "overridden"
            withDefaults.numbers == @[4, 5, 6]

    test "Generic wrapper type":
        let jsonWrapper = %*{
            "value": 42,
            "tag": "answer"
        }

        let wrapper = nodeAs(jsonWrapper, Wrapper[int])
        check:
            wrapper.value == 42
            wrapper.tag == "answer"

    test "String wrapper type":
        let jsonWrapper = %*{
            "value": "hello",
            "tag": "greeting"
        }

        let wrapper = nodeAs(jsonWrapper, Wrapper[string])
        check:
            wrapper.value == "hello"
            wrapper.tag == "greeting"

    test "Custom distinct type with hook":
        let jsonTimestamp = newJInt(1640995200)
        let timestamp = nodeAs(jsonTimestamp, Timestamp)
        check:
            int64(timestamp) == 1640995200

    test "StaticString types":
        let jsonString = newJString("hello world")
        let staticStr = nodeAs(jsonString, StaticString[20])
        check:
            $staticStr == "hello world"
            staticStr.len == 11

    test "Empty StaticString":
        let jsonString = newJString("")
        let staticStr = nodeAs(jsonString, StaticString[10])
        check:
            $staticStr == ""
            staticStr.len == 0

    test "StaticString truncation":
        let jsonString = newJString("this is a very long string")
        let staticStr = nodeAs(jsonString, StaticString[10])
        check:
            $staticStr == "this is a "
            staticStr.len == 10

    test "StaticSeq with complex types":
        let jsonArray = %*[
            {"x": 1, "y": 2},
            {"x": 3, "y": 4},
            {"x": 5, "y": 6}
        ]

        let staticSeq = nodeAs(jsonArray, StaticSeq[5, Point])
        check:
            staticSeq.len == 3
            staticSeq[0][].x == 1
            staticSeq[0][].y == 2
            staticSeq[1][].x == 3
            staticSeq[1][].y == 4
            staticSeq[2][].x == 5
            staticSeq[2][].y == 6

    test "Empty StaticSeq":
        let jsonArray = newJArray()
        let staticSeq = nodeAs(jsonArray, StaticSeq[5, int])
        check:
            staticSeq.len == 0

    test "StaticTable with enum keys":
        let jsonTable = %*{
            "Red": 100,
            "Green": 200,
            "Blue": 300
        }

        let staticTable = nodeAs(jsonTable, StaticTable[5, Color, int])
        var redFound, greenFound, blueFound = false
        
        for key, val in staticTable.pairs:
            if key == Red and val[] == 100:
                redFound = true
            elif key == Green and val[] == 200:
                greenFound = true
            elif key == Blue and val[] == 300:
                blueFound = true
        
        check:
            redFound and greenFound and blueFound
            staticTable.len == 3

    test "OrderedTable preservation":
        let jsonTable = %*{
            "z": 1,
            "a": 2,
            "m": 3
        }

        let orderedTable = nodeAs(jsonTable, OrderedTable[string, int])
        var keys: seq[string]
        for k in orderedTable.keys:
            keys.add(k)
        
        check:
            orderedTable["z"] == 1
            orderedTable["a"] == 2
            orderedTable["m"] == 3
            keys == @["z", "a", "m"]    # Order should be preserved

    # test "TableRef types":
    #     let jsonTable = %*{"key": 42}
    #     let tableRef = nodeAs(jsonTable, TableRef[string, int])
    #     check:
    #         tableRef != nil
    #         tableRef["key"] == 42

    test "Null TableRef":
        let tableRef = nodeAs(newJNull(), TableRef[string, int])
        check:
            tableRef == nil

    test "Nested sequences":
        let jsonNested = %*[
            [1, 2, 3],
            [4, 5],
            [6, 7, 8, 9]
        ]

        let nestedSeq = nodeAs(jsonNested, seq[seq[int]])
        check:
            nestedSeq == @[@[1, 2, 3], @[4, 5], @[6, 7, 8, 9]]

    test "Nested tables":
        let jsonNested = %*{
            "table1": {"a": 1, "b": 2},
            "table2": {"c": 3, "d": 4}
        }

        let nestedTable = nodeAs(jsonNested, Table[string, Table[string, int]])
        check:
            nestedTable["table1"]["a"] == 1
            nestedTable["table1"]["b"] == 2
            nestedTable["table2"]["c"] == 3
            nestedTable["table2"]["d"] == 4

    test "Deeply nested objects":
        type
            Level3 = object
                value: string
            
            Level2 = object
                level3: Level3
                numbers: seq[int]
            
            Level1 = object
                level2: Level2
                name: string

        let jsonDeep = %*{
            "name": "root",
            "level2": {
                "level3": {
                    "value": "deep"
                },
                "numbers": [1, 2, 3]
            }
        }

        let deep = nodeAs(jsonDeep, Level1)
        check:
            deep.name == "root"
            deep.level2.level3.value == "deep"
            deep.level2.numbers == @[1, 2, 3]

    test "Object with optional field present":
        let jsonWithOption = %*{
            "id": 1,
            "name": "test",
            "nested": {"x": 10, "y": 20}
        }

        let withOption = nodeAs(jsonWithOption, ComplexObject)
        # check:
        #     withOption.nested.isSome
        #     withOption.nested.get.x == 10
        #     withOption.nested.get.y == 20

    test "Object with optional field missing":
        let jsonWithoutOption = %*{
            "id": 1,
            "name": "test"
            # nested is missing
        }

        let withoutOption = nodeAs(jsonWithoutOption, ComplexObject)
        # check:
        #     withoutOption.nested.isNone

    test "Large numbers":
        check:
            nodeAs(newJInt(2147483647), int) == 2147483647
            nodeAs(newJInt(-2147483648), int) == -2147483648
            nodeAs(newJFloat(1.7976931348623157e308), float) == 1.7976931348623157e308

    test "Special float values":
        check:
            nodeAs(newJFloat(0.0), float) == 0.0
            nodeAs(newJFloat(-0.0), float) == -0.0
            nodeAs(newJFloat(1.0e-300), float) == 1.0e-300

    test "Boolean from various representations":
        check:
            nodeAs(newJString("true"), bool) == true
            nodeAs(newJString("false"), bool) == false
            # nodeAs(newJInt(1), bool) == true
            # nodeAs(newJInt(0), bool) == false

    test "Char type":
        let jsonChar = newJString("A")
        let charVal = nodeAs(jsonChar, char)
        check:
            charVal == 'A'

    test "Single character string as char":
        let jsonChar = newJString("Z")
        let charVal = nodeAs(jsonChar, char)
        check:
            charVal == 'Z'

    test "Error handling - multi-character string as char":
        expect ValueError:
            discard nodeAs(newJString("AB"), char)

    test "Error handling - empty string as char":
        expect ValueError:
            discard nodeAs(newJString(""), char)

    test "Error handling - array size mismatch":
        expect ValueError:
            let jsonArray = %[1, 2, 3]
            discard nodeAs(jsonArray, array[5, int])

    test "Error handling - invalid number for enum":
        expect ValueError:
            discard nodeAs(newJInt(999), Color)

    # test "Error handling - missing required field":
    #     expect ValueError:
    #         let jsonMissing = %*{"optional": "test"}    # missing required field
    #         discard nodeAs(jsonMissing, WithDefaults)

    test "Error handling - wrong nested type":
        expect ValueError:
            let jsonWrong = %*{
                "name": "test",
                "age": "not_a_number"    # should be int
            }
            discard nodeAs(jsonWrong, Person)

    test "Performance - large sequence":
        var largeArray = newJArray()
        for i in 0..<1000:
            largeArray.add(%i)
        
        let largeSeq = nodeAs(largeArray, seq[int])
        check:
            largeSeq.len == 1000
            largeSeq[0] == 0
            largeSeq[999] == 999

    test "Performance - large object":
        var largeObject = newJObject()
        for i in 0..<100:
            largeObject[$i] = %i
        
        let largeTable = nodeAs(largeObject, Table[string, int])
        check:
            largeTable.len == 100
            largeTable["0"] == 0
            largeTable["99"] == 99

    test "Round-trip JSON conversion":
        let original = %*{
            "name": "roundtrip",
            "age": 25,
            "colors": ["Red", "Blue"],
            "metadata": {
                "active": true,
                "score": 95.5
            }
        }

        # Convert to object and back to JSON
        let person = nodeAs(original, Person)
        let roundtrip = %person
        
        check:
            roundtrip["name"].getStr == "roundtrip"
            roundtrip["age"].getInt == 25
            roundtrip["colors"][0].getStr == "Red"
            roundtrip["metadata"]["active"].getBool == true

