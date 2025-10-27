import unittest

import hfutils_nim/json
import std/[strformat]

var testsPassed = 0
var testsFailed = 0

template test(name: string, body: untyped) =
    try:
        body
        inc testsPassed
        echo "✓ ", name
    except Exception as e:
        inc testsFailed
        echo "✗ ", name, ": ", e.msg

# Basic Types Tests
echo "\n=== Basic Types ==="

test "bool true":
    let result = jsonAs("true", bool)
    doAssert result == true

test "bool false":
    let result = jsonAs("false", bool)
    doAssert result == false

test "int positive":
    let result = jsonAs("42", int)
    doAssert result == 42

test "int negative":
    let result = jsonAs("-123", int)
    doAssert result == -123

test "int zero":
    let result = jsonAs("0", int)
    doAssert result == 0

test "uint":
    let result = jsonAs("999", uint)
    doAssert result == 999

test "float simple":
    let result = jsonAs("3.14", float)
    doAssert abs(result - 3.14) < 0.001

test "float negative":
    let result = jsonAs("-2.5", float)
    doAssert abs(result - (-2.5)) < 0.001

test "float scientific":
    let result = jsonAs("1.5e2", float)
    doAssert abs(result - 150.0) < 0.001

test "string simple":
    let result = jsonAs("\"hello\"", string)
    doAssert result == "hello"

test "string empty":
    let result = jsonAs("\"\"", string)
    doAssert result == ""

test "string with escape":
    let result = jsonAs("\"hello\\\"world\"", string)
    doAssert result == "hello\"world"

test "string null":
    let result = jsonAs("null", string)
    doAssert result == ""

test "char":
    let result = jsonAs("\"a\"", char)
    doAssert result == 'a'

# Enum Tests
echo "\n=== Enums ==="

type Color = enum
    Red, Green, Blue

test "enum from string":
    let result = jsonAs("\"Red\"", Color)
    doAssert result == Red

test "enum without quotes":
    let result = jsonAs("Green", Color)
    doAssert result == Green

type
    Animal = enum
        Dog, Cat, Bird, Fish
    
    Size = enum
        Small, Medium, Large, ExtraLarge
    
    Status = enum
        Active, Inactive, Pending, Suspended

test "enum all values":
    doAssert jsonAs("\"Dog\"", Animal) == Dog
    doAssert jsonAs("\"Cat\"", Animal) == Cat
    doAssert jsonAs("\"Bird\"", Animal) == Bird
    doAssert jsonAs("\"Fish\"", Animal) == Fish

test "enum case sensitive":
    doAssert jsonAs("\"Small\"", Size) == Small
    doAssert jsonAs("Small", Size) == Small

test "enum in sequence":
    let result = jsonAs("[\"Red\", \"Green\", \"Blue\"]", seq[Color])
    doAssert result == @[Red, Green, Blue]

test "enum in array":
    let result = jsonAs("[\"Dog\", \"Cat\"]", array[2, Animal])
    doAssert result == [Dog, Cat]

# Objects with Enums
echo "\n=== Objects with Enums ==="

type
    Pet = object
        name: string
        species: Animal
        size: Size
    
    PetStore = object
        name: string
        pets: seq[Pet]
        status: Status

test "simple object with enum":
    let json = """{"name": "Fluffy", "species": "Cat", "size": "Medium"}"""
    let result = jsonAs(json, Pet)
    doAssert result.name == "Fluffy"
    doAssert result.species == Cat
    doAssert result.size == Medium

test "object with multiple enums":
    let json = """{"name": "Buddy", "species": "Dog", "size": "Large"}"""
    let result = jsonAs(json, Pet)
    doAssert result.name == "Buddy"
    doAssert result.species == Dog
    doAssert result.size == Large

test "nested object with enums":
    let json = """{
        "name": "Pet Paradise",
        "pets": [
            {"name": "Rex", "species": "Dog", "size": "Large"},
            {"name": "Whiskers", "species": "Cat", "size": "Small"},
            {"name": "Tweety", "species": "Bird", "size": "Small"}
        ],
        "status": "Active"
    }"""
    let result = jsonAs(json, PetStore)
    doAssert result.name == "Pet Paradise"
    doAssert result.pets.len == 3
    doAssert result.pets[0].species == Dog
    doAssert result.pets[1].species == Cat
    doAssert result.pets[2].species == Bird
    doAssert result.pets[0].size == Large
    doAssert result.pets[1].size == Small
    doAssert result.status == Active

type
    HttpMethod = enum
        GET, POST, PUT, DELETE, PATCH
    
    ContentType = enum
        JSON, XML, HTML, PlainText
    
    HttpStatus = enum
        OK = 200
        Created = 201
        BadRequest = 400
        NotFound = 404
        ServerError = 500
    
    HttpRequest = object
        meth: HttpMethod
        path: string
        contentType: ContentType
    
    HttpResponse = object
        status: HttpStatus
        contentType: ContentType
        body: string
    
    ApiLog = object
        request: HttpRequest
        response: HttpResponse
        timestamp: int

test "http request with enums":
    let json = """{
        "meth": "POST",
        "path": "/api/users",
        "contentType": "JSON"
    }"""
    let result = jsonAs(json, HttpRequest)
    doAssert result.meth == POST
    doAssert result.path == "/api/users"
    doAssert result.contentType == JSON

test "http response with enum values":
    let json = """{
        "status": "OK",
        "contentType": "JSON",
        "body": "{\"success\": true}"
    }"""
    let result = jsonAs(json, HttpResponse)
    doAssert result.status == OK
    doAssert result.contentType == JSON

test "complex api log with multiple enums":
    let json = """{
        "request": {
            "meth": "GET",
            "path": "/api/data",
            "contentType": "JSON"
        },
        "response": {
            "status": "NotFound",
            "contentType": "JSON",
            "body": "{\"error\": \"Not found\"}"
        },
        "timestamp": 1234567890
    }"""
    let result = jsonAs(json, ApiLog)
    doAssert result.request.meth == GET
    doAssert result.response.status == NotFound
    doAssert result.timestamp == 1234567890

type
    TrafficLight = enum
        RedLight, YellowLight, GreenLight
    
    Direction = enum
        North, South, East, West
    
    Intersection = object
        id: int
        lights: Table[Direction, TrafficLight]

test "table with enum keys and values":
    let json = """{
        "id": 1,
        "lights": {
            "North": "RedLight",
            "South": "GreenLight",
            "East": "RedLight",
            "West": "GreenLight"
        }
    }"""
    let result = jsonAs(json, Intersection)
    doAssert result.id == 1
    doAssert result.lights[North] == RedLight
    doAssert result.lights[South] == GreenLight
    doAssert result.lights[East] == RedLight
    doAssert result.lights[West] == GreenLight

type
    WeatherCondition = enum
        Sunny, Cloudy, Rainy, Snowy, Stormy
    
    Temperature = enum
        Freezing, Cold, Cool, Mild, Warm, Hot
    
    WeatherReport = ref object
        condition: WeatherCondition
        temperature: Temperature
        windSpeed: float

test "ref object with enums":
    let json = """{
        "condition": "Rainy",
        "temperature": "Cool",
        "windSpeed": 15.5
    }"""
    let result = jsonAs(json, WeatherReport)
    doAssert result != nil
    doAssert result.condition == Rainy
    doAssert result.temperature == Cool
    doAssert abs(result.windSpeed - 15.5) < 0.001

test "ref object with enums null":
    let result = jsonAs("null", WeatherReport)
    doAssert result == nil

# Enum Dump Tests
echo "\n=== Enum Dump Tests ==="

test "dump enum":
    doAssert jsonDump(Red) == "\"Red\""
    doAssert jsonDump(Dog) == "\"Dog\""
    doAssert jsonDump(POST) == "\"POST\""

test "dump object with enums":
    let pet = Pet(name: "Spot", species: Dog, size: Large)
    let json = jsonDump(pet)
    doAssert "Spot" in json
    doAssert "Dog" in json
    doAssert "Large" in json

test "dump seq of enums":
    let colors = @[Red, Green, Blue]
    doAssert jsonDump(colors) == """["Red", "Green", "Blue"]"""

# Enum Round-trip Tests
echo "\n=== Enum Round-trip Tests ==="

test "round-trip pet with enums":
    let original = Pet(name: "Max", species: Dog, size: Medium)
    let json = jsonDump(original)
    let parsed = jsonAs(json, Pet)
    doAssert parsed.name == original.name
    doAssert parsed.species == original.species
    doAssert parsed.size == original.size

test "round-trip pet store":
    let original = PetStore(
        name: "Store",
        pets: @[
            Pet(name: "A", species: Cat, size: Small),
            Pet(name: "B", species: Dog, size: Large)
        ],
        status: Active
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, PetStore)
    doAssert parsed.name == original.name
    doAssert parsed.pets.len == original.pets.len
    doAssert parsed.pets[0].species == original.pets[0].species
    doAssert parsed.status == original.status

test "round-trip http request":
    let original = HttpRequest(
        meth: PUT,
        path: "/api/update",
        contentType: XML
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, HttpRequest)
    doAssert parsed.meth == original.meth
    doAssert parsed.path == original.path
    doAssert parsed.contentType == original.contentType

test "round-trip intersection with enum table":
    var lights: Table[Direction, TrafficLight]
    lights[North] = RedLight
    lights[South] = GreenLight
    let original = Intersection(id: 5, lights: lights)
    let json = jsonDump(original)
    let parsed = jsonAs(json, Intersection)
    doAssert parsed.id == original.id
    doAssert parsed.lights[North] == original.lights[North]
    doAssert parsed.lights[South] == original.lights[South]

# Enum Error Cases
echo "\n=== Enum Error Cases ==="

test "invalid enum value throws":
    try:
        discard jsonAs("\"InvalidColor\"", Color)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "invalid enum in object throws":
    try:
        let json = """{"name": "Test", "species": "InvalidAnimal", "size": "Medium"}"""
        discard jsonAs(json, Pet)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

# Sequence Tests
echo "\n=== Sequences ==="

test "seq of int":
    let result = jsonAs("[1, 2, 3, 4, 5]", seq[int])
    doAssert result == @[1, 2, 3, 4, 5]

test "seq empty":
    let result = jsonAs("[]", seq[int])
    doAssert result.len == 0

test "seq of string":
    let result = jsonAs("[\"a\", \"b\", \"c\"]", seq[string])
    doAssert result == @["a", "b", "c"]

test "seq of float":
    let result = jsonAs("[1.1, 2.2, 3.3]", seq[float])
    doAssert result.len == 3
    doAssert abs(result[0] - 1.1) < 0.001

test "seq nested":
    let result = jsonAs("[[1, 2], [3, 4]]", seq[seq[int]])
    doAssert result == @[@[1, 2], @[3, 4]]

test "seq null":
    let result = jsonAs("null", seq[int])
    doAssert result.len == 0

# Array Tests
echo "\n=== Arrays ==="

test "array of int":
    let result = jsonAs("[1, 2, 3]", array[3, int])
    doAssert result == [1, 2, 3]

test "array of string":
    let result = jsonAs("[\"x\", \"y\"]", array[2, string])
    doAssert result == ["x", "y"]

# Table Tests
echo "\n=== Tables ==="

test "table string to int":
    let result = jsonAs("{\"a\": 1, \"b\": 2}", Table[string, int])
    doAssert result["a"] == 1
    doAssert result["b"] == 2

test "table empty":
    let result = jsonAs("{}", Table[string, int])
    doAssert result.len == 0

test "table nested":
    let result = jsonAs("{\"x\": {\"y\": 1}}", Table[string, Table[string, int]])
    doAssert result["x"]["y"] == 1

test "table null":
    let result = jsonAs("null", Table[string, int])
    doAssert result.len == 0

# Object Tests
echo "\n=== Objects ==="

type Person = object
    name: string
    age: int
    active: bool

test "simple object":
    let result = jsonAs("{\"name\": \"Alice\", \"age\": 30, \"active\": true}", Person)
    doAssert result.name == "Alice"
    doAssert result.age == 30
    doAssert result.active == true

test "object partial fields":
    let result = jsonAs("{\"name\": \"Bob\"}", Person)
    doAssert result.name == "Bob"
    doAssert result.age == 0  # default value

test "object extra fields":
    let result = jsonAs("{\"name\": \"Charlie\", \"age\": 25, \"extra\": \"ignored\"}", Person)
    doAssert result.name == "Charlie"
    doAssert result.age == 25

test "object null":
    let result = jsonAs("null", Person)
    doAssert result.name == ""
    doAssert result.age == 0

type Address = object
    street: string
    city: string

type PersonWithAddress = object
    name: string
    address: Address

test "nested object":
    let json = """{"name": "Dave", "address": {"street": "Main St", "city": "NYC"}}"""
    let result = jsonAs(json, PersonWithAddress)
    doAssert result.name == "Dave"
    doAssert result.address.street == "Main St"
    doAssert result.address.city == "NYC"

# Ref Object Tests
echo "\n=== Ref Objects ==="

type PersonRef = ref object
    name: string
    age: int

test "ref object":
    let result = jsonAs("{\"name\": \"Eve\", \"age\": 28}", PersonRef)
    doAssert result != nil
    doAssert result.name == "Eve"
    doAssert result.age == 28

test "ref object null":
    let result = jsonAs("null", PersonRef)
    doAssert result == nil

# Complex Nested Structures
echo "\n=== Complex Structures ==="

type Company = object
    name: string
    employees: seq[Person]
    founded: int

test "complex nested structure":
    let json = """{
        "name": "TechCorp",
        "employees": [
            {"name": "Alice", "age": 30, "active": true},
            {"name": "Bob", "age": 25, "active": false}
        ],
        "founded": 2020
    }"""
    let result = jsonAs(json, Company)
    doAssert result.name == "TechCorp"
    doAssert result.employees.len == 2
    doAssert result.employees[0].name == "Alice"
    doAssert result.employees[1].age == 25
    doAssert result.founded == 2020

# JsonNode Tests
echo "\n=== JsonNode ==="

test "JsonNode object":
    let result = jsonAs("{\"a\": 1, \"b\": \"test\"}", JsonNode)
    doAssert result.kind == JObject
    doAssert result["a"].getInt() == 1
    doAssert result["b"].getStr() == "test"

test "JsonNode array":
    let result = jsonAs("[1, 2, 3]", JsonNode)
    doAssert result.kind == JArray
    doAssert result.len == 3

# Whitespace Handling
echo "\n=== Whitespace Handling ==="

test "whitespace in object":
    let result = jsonAs("  {  \"name\"  :  \"Test\"  }  ", Person)
    doAssert result.name == "Test"

test "whitespace in array":
    let result = jsonAs("  [  1  ,  2  ,  3  ]  ", seq[int])
    doAssert result == @[1, 2, 3]

# JSON Dump Tests
echo "\n=== JSON Dump ==="

test "dump int":
    doAssert jsonDump(42) == "42"

test "dump bool":
    doAssert jsonDump(true) == "true"

test "dump string":
    doAssert jsonDump("hello") == "\"hello\""

test "dump seq":
    doAssert jsonDump(@[1, 2, 3]) == "[1, 2, 3]"

test "dump object":
    let p = Person(name: "Alice", age: 30, active: true)
    let json = jsonDump(p)
    doAssert "Alice" in json
    doAssert "30" in json

test "dump table":
    var t: Table[string, int]
    t["a"] = 1
    t["b"] = 2
    let json = jsonDump(t)
    doAssert "a" in json and "1" in json

test "dump null ref":
    let p: PersonRef = nil
    doAssert jsonDump(p) == "null"

# Round-trip Tests
echo "\n=== Round-trip Tests ==="

test "round-trip Person":
    let original = Person(name: "Test", age: 42, active: true)
    let json = jsonDump(original)
    let parsed = jsonAs(json, Person)
    doAssert parsed.name == original.name
    doAssert parsed.age == original.age
    doAssert parsed.active == original.active

test "round-trip seq[int]":
    let original = @[1, 2, 3, 4, 5]
    let json = jsonDump(original)
    let parsed = jsonAs(json, seq[int])
    doAssert parsed == original

test "round-trip nested":
    let original = @[@[1, 2], @[3, 4], @[5, 6]]
    let json = jsonDump(original)
    let parsed = jsonAs(json, seq[seq[int]])
    doAssert parsed == original

# Error Cases
echo "\n=== Error Handling ==="

test "invalid bool throws":
    try:
        discard jsonAs("invalid", bool)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "invalid int throws":
    try:
        discard jsonAs("not_a_number", int)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "unclosed string throws":
    try:
        discard jsonAs("\"unclosed", string)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "unclosed array throws":
    try:
        discard jsonAs("[1, 2, 3", seq[int])
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "wrong array size throws":
    try:
        discard jsonAs("[1, 2]", array[3, int])
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "invalid char throws":
    try:
        discard jsonAs("\"ab\"", char)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

# Static Types Tests
echo "\n=== Static Types ==="

test "StaticString basic":
    let json = "\"hello\""
    let result = jsonAs(json, StaticString[32])
    doAssert result == "hello"
    doAssert result.len == 5

test "StaticString empty":
    let json = "\"\""
    let result = jsonAs(json, StaticString[32])
    doAssert result == ""
    doAssert result.len == 0

test "StaticString max capacity":
    let longStr = "a".repeat(32)
    let json = "\"" & longStr & "\""
    let result = jsonAs(json, StaticString[32])
    doAssert result.len == 32

test "StaticString with spaces":
    let json = "\"hello world\""
    let result = jsonAs(json, StaticString[64])
    doAssert result == "hello world"

test "StaticSeq of int":
    let json = "[1, 2, 3, 4, 5]"
    let result = jsonAs(json, StaticSeq[10, int])
    doAssert result.len == 5
    doAssert result[0][] == 1
    doAssert result[4][] == 5

test "StaticSeq empty":
    let json = "[]"
    let result = jsonAs(json, StaticSeq[10, int])
    doAssert result.len == 0

test "StaticSeq of float":
    let json = "[1.1, 2.2, 3.3]"
    let result = jsonAs(json, StaticSeq[10, float])
    doAssert result.len == 3
    doAssert abs(result[0][] - 1.1) < 0.001
    doAssert abs(result[1][] - 2.2) < 0.001

test "StaticSeq at capacity":
    let json = "[1, 2, 3, 4, 5]"
    let result = jsonAs(json, StaticSeq[5, int])
    doAssert result.len == 5

test "StaticTable string to int":
    let json = "{\"a\": 1, \"b\": 2, \"c\": 3}"
    let result = jsonAs(json, StaticTable[10, StaticString[32], int])
    var lookup: Table[StaticString[32], int]
    doAssert result.len == 3
    doAssert result.get("a".toStatic[:32], lookup) == 1
    doAssert result.get("b".toStatic[:32], lookup) == 2
    doAssert result.get("c".toStatic[:32], lookup) == 3

test "StaticTable empty":
    let json = "{}"
    let result = jsonAs(json, StaticTable[10, StaticString[32], int])
    doAssert result.len == 0

test "StaticTable with StaticString keys":
    let json = "{\"key1\": 100, \"key2\": 200}"
    let result = jsonAs(json, StaticTable[10, StaticString[32], int])
    var lookup: Table[StaticString[32], int]
    doAssert result.len == 2
    doAssert result.get("key1".toStatic[:32], lookup) == 100
    doAssert result.get("key2".toStatic[:32], lookup) == 200

# Objects with Static Types
echo "\n=== Objects with Static Types ==="

type
    UserProfile = object
        username: StaticString[32]
        email: StaticString[64]
        age: int
    
    Message = object
        sender: StaticString[32]
        content: StaticString[256]
        timestamp: int
    
    Config = object
        name: StaticString[64]
        values: StaticSeq[10, int]
        settings: StaticTable[5, StaticString[32], StaticString[64]]

test "object with StaticString fields":
    let json = """{
        "username": "alice123",
        "email": "alice@example.com",
        "age": 25
    }"""
    let result = jsonAs(json, UserProfile)
    doAssert result.username == "alice123"
    doAssert result.email == "alice@example.com"
    doAssert result.age == 25

test "object with StaticString and StaticSeq":
    let json = """{
        "name": "MyConfig",
        "values": [1, 2, 3, 4],
        "settings": {"key1": "value1", "key2": "value2"}
    }"""
    let result = jsonAs(json, Config)
    var lookup: Table[StaticString[32], int]
    doAssert result.name == "MyConfig"
    doAssert result.values.len == 4
    doAssert result.values[2][] == 3
    doAssert result.settings.len == 2
    doAssert result.settings.get("key1".toStatic[:32], lookup) == "value1"

type
    ChatRoom = object
        name: StaticString[64]
        messages: StaticSeq[100, Message]
        memberCount: int

test "nested static types":
    let json = """{
        "name": "General",
        "messages": [
            {"sender": "alice", "content": "Hello!", "timestamp": 1000},
            {"sender": "bob", "content": "Hi there!", "timestamp": 1001}
        ],
        "memberCount": 10
    }"""
    let result = jsonAs(json, ChatRoom)
    doAssert result.name == "General"
    doAssert result.messages.len == 2
    doAssert result.messages[0].sender == "alice"
    doAssert result.messages[1].content == "Hi there!"
    doAssert result.memberCount == 10

type
    DatabaseConfig = object
        host: StaticString[128]
        port: int
        credentials: StaticTable[5, StaticString[32], StaticString[64]]

test "object with StaticTable field":
    let json = """{
        "host": "localhost",
        "port": 5432,
        "credentials": {
            "username": "admin",
            "password": "secret123"
        }
    }"""
    let result = jsonAs(json, DatabaseConfig)
    var lookup: Table[StaticString[32], int]
    doAssert result.host == "localhost"
    doAssert result.port == 5432
    doAssert result.credentials.get("username".toStatic[:32], lookup) == "admin"
    doAssert result.credentials.get("password".toStatic[:32], lookup) == "secret123"

# Static Types Dump Tests
echo "\n=== Static Types Dump ==="

test "dump StaticString":
    let s = "test".toStatic[:32]
    let json = jsonDump(s)
    doAssert json == "\"test\""

test "dump StaticSeq":
    var seq: StaticSeq[10, int]
    seq.add(1)
    seq.add(2)
    seq.add(3)
    let json = jsonDump(seq)
    doAssert json == "[1, 2, 3]"

test "dump StaticTable":
    var table: StaticTable[10, StaticString[32], int]
    table.add("a".toStatic[:32], 1, skipLookupTable = true)
    table.add("b".toStatic[:32], 2, skipLookupTable = true)
    let json = jsonDump(table)
    doAssert "\"a\"" in json
    doAssert "1" in json
    doAssert "\"b\"" in json
    doAssert "2" in json

test "dump UserProfile with static types":
    let profile = UserProfile(
        username: "test_user".toStatic[:32],
        email: "test@example.com".toStatic[:64],
        age: 30
    )
    let json = jsonDump(profile)
    doAssert "\"test_user\"" in json
    doAssert "\"test@example.com\"" in json
    doAssert "30" in json

# Static Types Round-trip Tests
echo "\n=== Static Types Round-trip ==="

test "round-trip StaticString":
    let original = "hello world".toStatic[:32]
    let json = jsonDump(original)
    let parsed = jsonAs(json, StaticString[32])
    doAssert parsed == original

test "round-trip StaticSeq":
    var original: StaticSeq[10, int]
    original.add(10)
    original.add(20)
    original.add(30)
    let json = jsonDump(original)
    let parsed = jsonAs(json, StaticSeq[10, int])
    doAssert parsed.len == original.len
    doAssert parsed[0][] == original[0][]
    doAssert parsed[1][] == original[1][]
    doAssert parsed[2][] == original[2][]

test "round-trip UserProfile":
    let original = UserProfile(
        username: "alice".toStatic[:32],
        email: "alice@test.com".toStatic[:64],
        age: 28
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, UserProfile)
    doAssert parsed.username == original.username
    doAssert parsed.email == original.email
    doAssert parsed.age == original.age

test "round-trip ChatRoom":
    var msg1 = Message(
        sender: "user1".toStatic[:32],
        content: "Hello".toStatic[:256],
        timestamp: 1000
    )
    var msg2 = Message(
        sender: "user2".toStatic[:32],
        content: "World".toStatic[:256],
        timestamp: 2000
    )
    var messages: StaticSeq[100, Message]
    messages.add(msg1)
    messages.add(msg2)
    let original = ChatRoom(
        name: "TestRoom".toStatic[:64],
        messages: messages,
        memberCount: 5
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, ChatRoom)
    doAssert parsed.name == original.name
    doAssert parsed.messages.len == original.messages.len
    doAssert parsed.messages[0].sender == original.messages[0].sender
    doAssert parsed.memberCount == original.memberCount

# Mixed Static and Dynamic Types
echo "\n=== Mixed Static and Dynamic Types ==="

type
    HybridConfig = object
        staticName: StaticString[32]
        dynamicName: string
        staticValues: StaticSeq[5, int]
        dynamicValues: seq[int]
    
    ComplexData = object
        id: int
        tags: seq[StaticString[16]]
        metadata: Table[string, StaticString[64]]

test "object with mixed static and dynamic fields":
    let json = """{
        "staticName": "static",
        "dynamicName": "dynamic",
        "staticValues": [1, 2, 3],
        "dynamicValues": [4, 5, 6, 7]
    }"""
    let result = jsonAs(json, HybridConfig)
    doAssert result.staticName == "static"
    doAssert result.dynamicName == "dynamic"
    doAssert result.staticValues.len == 3
    doAssert result.dynamicValues.len == 4
    doAssert result.dynamicValues[3] == 7

test "seq of static strings":
    let json = """{"id": 1, "tags": ["tag1", "tag2", "tag3"], "metadata": {}}"""
    let result = jsonAs(json, ComplexData)
    doAssert result.id == 1
    doAssert result.tags.len == 3
    doAssert result.tags[0] == "tag1"
    doAssert result.tags[1] == "tag2"

test "round-trip hybrid config":
    var staticVals: StaticSeq[5, int]
    staticVals.add(1)
    staticVals.add(2)
    let original = HybridConfig(
        staticName: "test".toStatic[:32],
        dynamicName: "dynamic_test",
        staticValues: staticVals,
        dynamicValues: @[10, 20, 30]
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, HybridConfig)
    doAssert parsed.staticName == original.staticName
    doAssert parsed.dynamicName == original.dynamicName
    doAssert parsed.staticValues.len == original.staticValues.len
    doAssert parsed.dynamicValues == original.dynamicValues

# Static Types Error Cases
echo "\n=== Static Types Error Cases ==="

test "StaticSeq too many elements":
    try:
        let json = "[1, 2, 3, 4, 5, 6]"
        discard jsonAs(json, StaticSeq[5, int])
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "StaticTable too many elements":
    try:
        let json = """{"a": 1, "b": 2, "c": 3}"""
        discard jsonAs(json, StaticTable[2, StaticString[3], int])
        doAssert false, "Should have thrown"
    except ValueError:
        discard

# Advanced Custom Types
echo "\n=== Advanced Custom Types ==="

type
    Priority = enum
        Low, Medium, High, Critical
    
    TaskStatus = enum
        Todo, InProgress, Done, Archived
    
    Tag = object
        name: string
        color: string
    
    Task = object
        id: int
        title: string
        description: string
        priority: Priority
        status: TaskStatus
        tags: seq[Tag]
        assignees: seq[string]
        subtasks: seq[Task]
    
    Project = object
        name: string
        tasks: seq[Task]
        metadata: Table[string, string]

test "complex task object":
    let json = """{
        "id": 1,
        "title": "Implement feature",
        "description": "Add new functionality",
        "priority": "High",
        "status": "InProgress",
        "tags": [
            {"name": "frontend", "color": "blue"},
            {"name": "urgent", "color": "red"}
        ],
        "assignees": ["alice", "bob"],
        "subtasks": []
    }"""
    let result = jsonAs(json, Task)
    doAssert result.id == 1
    doAssert result.title == "Implement feature"
    doAssert result.priority == High
    doAssert result.status == InProgress
    doAssert result.tags.len == 2
    doAssert result.tags[0].name == "frontend"
    doAssert result.assignees == @["alice", "bob"]

test "deeply nested tasks":
    let json = """{
        "id": 1,
        "title": "Parent Task",
        "description": "Top level",
        "priority": "Critical",
        "status": "Todo",
        "tags": [],
        "assignees": [],
        "subtasks": [
            {
                "id": 2,
                "title": "Subtask 1",
                "description": "First subtask",
                "priority": "Medium",
                "status": "Done",
                "tags": [],
                "assignees": ["alice"],
                "subtasks": [
                    {
                        "id": 3,
                        "title": "Sub-subtask",
                        "description": "Nested deep",
                        "priority": "Low",
                        "status": "Todo",
                        "tags": [],
                        "assignees": [],
                        "subtasks": []
                    }
                ]
            }
        ]
    }"""
    let result = jsonAs(json, Task)
    doAssert result.id == 1
    doAssert result.subtasks.len == 1
    doAssert result.subtasks[0].id == 2
    doAssert result.subtasks[0].subtasks.len == 1
    doAssert result.subtasks[0].subtasks[0].id == 3
    doAssert result.subtasks[0].subtasks[0].title == "Sub-subtask"

test "project with tasks and metadata":
    let json = """{
        "name": "MyProject",
        "tasks": [
            {
                "id": 1,
                "title": "Task 1",
                "description": "First",
                "priority": "Low",
                "status": "Done",
                "tags": [],
                "assignees": [],
                "subtasks": []
            },
            {
                "id": 2,
                "title": "Task 2",
                "description": "Second",
                "priority": "High",
                "status": "Todo",
                "tags": [],
                "assignees": ["bob"],
                "subtasks": []
            }
        ],
        "metadata": {
            "version": "1.0",
            "author": "team",
            "deadline": "2025-12-31"
        }
    }"""
    let result = jsonAs(json, Project)
    doAssert result.name == "MyProject"
    doAssert result.tasks.len == 2
    doAssert result.tasks[0].priority == Low
    doAssert result.tasks[1].status == Todo
    doAssert result.metadata["version"] == "1.0"
    doAssert result.metadata["deadline"] == "2025-12-31"

type
    Matrix = object
        rows: int
        cols: int
        data: seq[seq[float]]
    
    Vector3D = object
        x, y, z: float
    
    Transform = object
        position: Vector3D
        rotation: Vector3D
        scale: Vector3D
    
    Node = ref object
        name: string
        transform: Transform
        children: seq[Node]
        parent: Node

test "matrix with nested sequences":
    let json = """{
        "rows": 3,
        "cols": 3,
        "data": [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
        ]
    }"""
    let result = jsonAs(json, Matrix)
    doAssert result.rows == 3
    doAssert result.cols == 3
    doAssert result.data.len == 3
    doAssert result.data[0] == @[1.0, 0.0, 0.0]
    doAssert result.data[1][1] == 1.0

test "transform with vector3d":
    let json = """{
        "position": {"x": 1.5, "y": 2.5, "z": 3.5},
        "rotation": {"x": 0.0, "y": 90.0, "z": 0.0},
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0}
    }"""
    let result = jsonAs(json, Transform)
    doAssert abs(result.position.x - 1.5) < 0.001
    doAssert abs(result.rotation.y - 90.0) < 0.001
    doAssert abs(result.scale.z - 1.0) < 0.001

test "scene graph with ref objects":
    let json = """{
        "name": "root",
        "transform": {
            "position": {"x": 0.0, "y": 0.0, "z": 0.0},
            "rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
            "scale": {"x": 1.0, "y": 1.0, "z": 1.0}
        },
        "children": [
            {
                "name": "child1",
                "transform": {
                    "position": {"x": 1.0, "y": 0.0, "z": 0.0},
                    "rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
                    "scale": {"x": 1.0, "y": 1.0, "z": 1.0}
                },
                "children": [],
                "parent": null
            }
        ],
        "parent": null
    }"""
    let result = jsonAs(json, Node)
    doAssert result.name == "root"
    doAssert result.children.len == 1
    doAssert result.children[0].name == "child1"
    doAssert result.parent == nil

type
    StudentGrade = object
        subject: string
        score: float
        letter: char
    
    Student = object
        id: int
        name: string
        grades: seq[StudentGrade]
        metadata: Table[string, JsonNode]
    
    Classroom = object
        name: string
        students: seq[Student]
        averageScore: float

test "classroom with mixed types":
    let json = """{
        "name": "Math 101",
        "students": [
            {
                "id": 1,
                "name": "Alice",
                "grades": [
                    {"subject": "Algebra", "score": 95.5, "letter": "A"},
                    {"subject": "Geometry", "score": 88.0, "letter": "B"}
                ],
                "metadata": {
                    "attendance": 0.95,
                    "notes": "Excellent student"
                }
            },
            {
                "id": 2,
                "name": "Bob",
                "grades": [
                    {"subject": "Algebra", "score": 78.5, "letter": "C"}
                ],
                "metadata": {
                    "attendance": 0.80
                }
            }
        ],
        "averageScore": 86.75
    }"""
    let result = jsonAs(json, Classroom)
    doAssert result.name == "Math 101"
    doAssert result.students.len == 2
    doAssert result.students[0].grades.len == 2
    doAssert result.students[0].grades[0].letter == 'A'
    doAssert abs(result.students[0].grades[0].score - 95.5) < 0.001
    doAssert result.students[0].metadata["notes"].getStr() == "Excellent student"
    doAssert abs(result.averageScore - 86.75) < 0.001

type
    ConfigValue = object
        key: string
        value: JsonNode
        encrypted: bool
    
    NestedConfig = object
        section: string
        values: seq[ConfigValue]
        subsections: seq[NestedConfig]

test "configuration with arbitrary json values":
    let json = """{
        "section": "database",
        "values": [
            {
                "key": "host",
                "value": "localhost",
                "encrypted": false
            },
            {
                "key": "port",
                "value": 5432,
                "encrypted": false
            },
            {
                "key": "credentials",
                "value": {"user": "admin", "pass": "secret"},
                "encrypted": true
            }
        ],
        "subsections": [
            {
                "section": "pool",
                "values": [
                    {
                        "key": "maxConnections",
                        "value": 100,
                        "encrypted": false
                    }
                ],
                "subsections": []
            }
        ]
    }"""
    let result = jsonAs(json, NestedConfig)
    doAssert result.section == "database"
    doAssert result.values.len == 3
    doAssert result.values[0].value.getStr() == "localhost"
    doAssert result.values[1].value.getInt() == 5432
    doAssert result.values[2].encrypted == true
    doAssert result.values[2].value["user"].getStr() == "admin"
    doAssert result.subsections.len == 1
    doAssert result.subsections[0].values[0].value.getInt() == 100

type
    OptionalFields = object
        required: string
        optional1: string
        optional2: int
        optional3: bool

test "object with missing optional fields":
    let json1 = """{"required": "test"}"""
    let result1 = jsonAs(json1, OptionalFields)
    doAssert result1.required == "test"
    doAssert result1.optional1 == ""
    doAssert result1.optional2 == 0
    doAssert result1.optional3 == false
    
    let json2 = """{"required": "test", "optional1": "set", "optional3": true}"""
    let result2 = jsonAs(json2, OptionalFields)
    doAssert result2.required == "test"
    doAssert result2.optional1 == "set"
    doAssert result2.optional2 == 0
    doAssert result2.optional3 == true

# Round-trip tests for complex types
echo "\n=== Complex Round-trip Tests ==="

test "round-trip task with tags":
    let original = Task(
        id: 42,
        title: "Test Task",
        description: "Description",
        priority: High,
        status: InProgress,
        tags: @[Tag(name: "test", color: "blue")],
        assignees: @["user1", "user2"],
        subtasks: @[]
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, Task)
    doAssert parsed.id == original.id
    doAssert parsed.title == original.title
    doAssert parsed.priority == original.priority
    doAssert parsed.tags.len == original.tags.len
    doAssert parsed.tags[0].name == original.tags[0].name

test "round-trip matrix":
    let original = Matrix(
        rows: 2,
        cols: 2,
        data: @[@[1.0, 2.0], @[3.0, 4.0]]
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, Matrix)
    doAssert parsed.rows == original.rows
    doAssert parsed.cols == original.cols
    doAssert parsed.data == original.data

test "round-trip classroom":
    let original = Classroom(
        name: "Test Class",
        students: @[
            Student(
                id: 1,
                name: "Student1",
                grades: @[StudentGrade(subject: "Math", score: 90.0, letter: 'A')],
                metadata: {"key": newJString("value")}.toTable
            )
        ],
        averageScore: 90.0
    )
    let json = jsonDump(original)
    let parsed = jsonAs(json, Classroom)
    doAssert parsed.name == original.name
    doAssert parsed.students.len == original.students.len
    doAssert parsed.students[0].name == original.students[0].name
    doAssert abs(parsed.averageScore - original.averageScore) < 0.001

# Add these test cases to the end of your existing test suite, before the summary

# Advanced Edge Cases
echo "\n=== Advanced Edge Cases ==="

test "empty object with extra whitespace":
    let json = "  {  }  "
    let result = jsonAs(json, Person)
    doAssert result.name == ""
    doAssert result.age == 0

test "object with only commas":
    let json = "{,,,}"
    try:
        discard jsonAs(json, Person)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

# test "malformed number with multiple decimals":
#     let json = "123.45.67"
#     try:
#         discard jsonAs(json, float)
#         doAssert false, "Should have thrown"
#     except ValueError:
#         discard

# test "number with exponent but no digits":
#     let json = "1.e"
#     try:
#         discard jsonAs(json, float)
#         doAssert false, "Should have thrown"
#     except ValueError:
#         discard

# test "string with unicode escape sequences":
#     let json = "\"\\u0041\\u0042\\u0043\""
#     let result = jsonAs(json, string)
#     doAssert result == "ABC"

#FIXME
# # test "string with mixed escape sequences":
#     let json = "\"line1\\nline2\\ttab\\\"quote\\\"\""
#     let result = jsonAs(json, string)
#     echo json
#     echo result
#     doAssert "line1\\nline2\\ttab\\\"quote\\\"" in result
#     quit(1)

test "negative zero":
    let json = "-0"
    let result = jsonAs(json, int)
    doAssert result == 0

test "float with positive exponent":
    let json = "1.5e+3"
    let result = jsonAs(json, float)
    doAssert abs(result - 1500.0) < 0.001

test "float with negative exponent":
    let json = "1.5e-2"
    let result = jsonAs(json, float)
    doAssert abs(result - 0.015) < 0.001

# Circular Reference Handling
echo "\n=== Circular Reference Tests ==="

type
    TreeNode = ref object
        name: string
        children: seq[TreeNode]
        parent: TreeNode

test "tree structure with circular references":
    let json = """{
        "name": "root",
        "children": [
            {
                "name": "child1",
                "children": [],
                "parent": null
            },
            {
                "name": "child2", 
                "children": [],
                "parent": null
            }
        ],
        "parent": null
    }"""
    let result = jsonAs(json, TreeNode)
    doAssert result.name == "root"
    doAssert result.children.len == 2
    doAssert result.children[0].name == "child1"
    doAssert result.children[1].name == "child2"

# Performance Stress Tests
echo "\n=== Performance Stress Tests ==="

test "large array of numbers":
    var json = "["
    for i in 0..<1000:
        if i > 0: json.add(",")
        json.add($i)
    json.add("]")
    let result = jsonAs(json, seq[int])
    doAssert result.len == 1000
    doAssert result[0] == 0
    doAssert result[999] == 999

test "large object with many fields":
    var json = "{"
    for i in 0..<100:
        if i > 0: json.add(",")
        json.add("\"field" & $i & "\":" & $i)
    json.add("}")
    let result = jsonAs(json, Table[string, int])
    doAssert result.len == 100
    doAssert result["field0"] == 0
    doAssert result["field99"] == 99

# # Complex Generic Types
# echo "\n=== Complex Generic Types ==="

# type
#     Result[T, E] = object
#         case isSuccess: bool
#         of true:
#             value: T
#         of false:
#             error: E
    
#     Either[A, B] = object
#         case isLeft: bool
#         of true:
#             left: A
#         of false:
#             right: B

# test "generic result type success":
#     let json = """{"isSuccess": true, "value": 42}"""
#     let result = jsonAs(json, Result[int, string])
#     doAssert result.isSuccess
#     doAssert result.value == 42

# test "generic  type error":
#     let json = """{"isSuccess": false, "error": "failed"}"""
#     let result = jsonAs(json, Result[int, string])
#     doAssert not result.isSuccess
#     doAssert result.error == "failed"

# test "generic either type left":
#     let json = """{"isLeft": true, "left": "data"}"""
#     let result = jsonAs(json, Either[string, int])
#     doAssert result.isLeft
#     doAssert result.left == "data"

# test "generic either type right":
#     let json = """{"isLeft": false, "right": 123}"""
#     let result = jsonAs(json, Either[string, int])
#     doAssert not result.isLeft
#     doAssert result.right == 123

# Advanced Enum Features
echo "\n=== Advanced Enum Features ==="

type
    EnumWithValues = enum
        First = "first_value",
        Second = "second_value",
        Third = "third_value"
    
    EnumWithHoles = enum
        Zero = 0,
        Two = 2,
        Four = 4,
        Six = 6

test "enum with string values":
    let result = jsonAs("\"first_value\"", EnumWithValues)
    doAssert result == First

test "enum with holes":
    let result = jsonAs("4", EnumWithHoles)
    doAssert result == Four

# Boundary Value Tests
echo "\n=== Boundary Value Tests ==="

test "int8 boundaries":
    doAssert jsonAs("127", int8) == 127
    doAssert jsonAs("-128", int8) == -128

test "uint8 boundaries":
    doAssert jsonAs("0", uint8) == 0
    doAssert jsonAs("255", uint8) == 255

test "int16 boundaries":
    doAssert jsonAs("32767", int16) == 32767
    doAssert jsonAs("-32768", int16) == -32768

test "float boundaries":
    doAssert jsonAs("1.7976931348623157e308", float32) == Inf
    doAssert jsonAs("-1.7976931348623157e308", float32) == -Inf
    doAssert jsonAs("0.0", float) == 0.0

#TODO
# # Special Float Values
# test "float special values":
#     let infResult = jsonAs("Infinity", float)
#     let negInfResult = jsonAs("-Infinity", float)
#     let nanResult = jsonAs("NaN", float)
#     doAssert infResult == Inf
#     doAssert negInfResult == -Inf
#     doAssert nanResult != nanResult  # NaN != NaN

# Complex Table Scenarios
echo "\n=== Complex Table Scenarios ==="

type
    NestedTable = object
        data: Table[string, Table[string, int]]
    
    TableWithComplexKeys = object
        mapping: Table[seq[string], int]  # This should fail as seq can't be table key

test "nested table structure":
    let json = """{
        "data": {
            "group1": {"a": 1, "b": 2},
            "group2": {"c": 3, "d": 4}
        }
    }"""
    let result = jsonAs(json, NestedTable)
    doAssert result.data["group1"]["a"] == 1
    doAssert result.data["group2"]["d"] == 4

# Error Recovery Tests
echo "\n=== Error Recovery Tests ==="

test "malformed object with recovery":
    let json = """{"name": "test", "age": 30, "extra": [1,2,3"""  # Missing closing braces
    try:
        discard jsonAs(json, Person)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "unterminated string":
    let json = "\"unterminated string"
    try:
        discard jsonAs(json, string)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

#FIXME
# test "invalid escape sequence":
#     let json = "\"invalid\\xescape\""
#     echo jsonAs(json, string)
#     try:
#         discard jsonAs(json, string)
#         doAssert false, "Should have thrown"
#     except ValueError:
#         discard

# Mixed Content Arrays
echo "\n=== Mixed Content Arrays ==="

type
    MixedArray = object
        items: seq[JsonNode]

test "array with mixed types":
    let json = """{
        "items": [1, "string", true, null, {"key": "value"}]
    }"""
    let result = jsonAs(json, MixedArray)
    doAssert result.items.len == 5
    doAssert result.items[0].getInt() == 1
    doAssert result.items[1].getStr() == "string"
    doAssert result.items[2].getBool() == true
    doAssert result.items[3].kind == JNull

# Unicode and Internationalization
echo "\n=== Unicode and Internationalization ==="

test "unicode strings":
    let json = "\"Hello 世界 🌍\""
    let result = jsonAs(json, string)
    doAssert result == "Hello 世界 🌍"

test "unicode in object keys":
    let json = """{"名字": "张三", "年龄": 25}"""
    let result = jsonAs(json, Table[string, JsonNode])
    doAssert result["名字"].getStr() == "张三"
    doAssert result["年龄"].getInt() == 25

# Memory Safety Tests
echo "\n=== Memory Safety Tests ==="

# test "null bytes in strings":
#     let json = "\"hello\\u0000world\""
#     let result = jsonAs(json, string)
#     doAssert result == "hello\0world"

test "very long strings":
    let longStr = "a".repeat(10000)
    let json = "\"" & longStr & "\""
    let result = jsonAs(json, string)
    doAssert result == longStr

# Concurrent Access Patterns
echo "\n=== Concurrent Access Patterns ==="

type
    SharedConfig = object
        counters: Table[string, int]
        values: seq[string]

test "concurrent-like structure":
    let json = """{
        "counters": {"requests": 1000, "errors": 5},
        "values": ["val1", "val2", "val3"]
    }"""
    let result = jsonAs(json, SharedConfig)
    doAssert result.counters["requests"] == 1000
    doAssert result.values.len == 3

# Advanced Static Type Scenarios
echo "\n=== Advanced Static Type Scenarios ==="

type
    FixedMatrix3x3 = StaticSeq[3, StaticSeq[3, float]]
    FixedVector4 = StaticSeq[4, float]

test "static matrix operations":
    var matrix: FixedMatrix3x3
    for i in 0..2:
        var row: StaticSeq[3, float]
        for j in 0..2:
            row.add(float(i * 3 + j))
        matrix.add(row)
    
    let json = jsonDump(matrix)
    let parsed = jsonAs(json, FixedMatrix3x3)
    doAssert parsed.len == 3
    doAssert parsed[0].len == 3

test "static type with maximum capacity":
    var maxSeq: StaticSeq[1000, int]
    for i in 0..<1000:
        maxSeq.add(i)
    
    let json = jsonDump(maxSeq)
    let parsed = jsonAs(json, StaticSeq[1000, int])
    doAssert parsed.len == 1000
    doAssert parsed[999][] == 999

# Complex Inheritance Scenarios
echo "\n=== Complex Inheritance Scenarios ==="

type
    BaseObject = object of RootObj
        baseField: string
    
    DerivedObject = object of BaseObject
        derivedField: int
    
    AnotherDerived = object of BaseObject
        anotherField: bool

test "inheritance with base class":
    let json = """{"baseField": "base", "derivedField": 42}"""
    let result = jsonAs(json, DerivedObject)
    doAssert result.baseField == "base"
    doAssert result.derivedField == 42

# Protocol Buffer Like Structures
echo "\n=== Protocol Buffer Like Structures ==="

type
    ProtoMessage = object
        id: int32
        name: string
        tags: seq[string]
        data: seq[byte]
        timestamp: int64
        isActive: bool
        metadata: Table[string, string]

test "protocol buffer like message":
    let json = """{
        "id": 123,
        "name": "test_message",
        "tags": ["important", "urgent"],
        "data": [1, 2, 3, 4, 5],
        "timestamp": 1633046400000,
        "isActive": true,
        "metadata": {"version": "1.0", "author": "system"}
    }"""
    let result = jsonAs(json, ProtoMessage)
    doAssert result.id == 123
    doAssert result.name == "test_message"
    doAssert result.tags == @["important", "urgent"]
    doAssert result.data == @[1.byte, 2, 3, 4, 5]
    doAssert result.timestamp == 1633046400000
    doAssert result.isActive == true
    doAssert result.metadata["version"] == "1.0"

# Database Record Like Structures
echo "\n=== Database Record Like Structures ==="

type
    UserRecord = object
        userId: int
        username: string
        email: string
        createdAt: string
        updatedAt: string
        profile: JsonNode
        permissions: seq[string]
        settings: Table[string, JsonNode]

test "database record structure":
    let json = """{
        "userId": 1,
        "username": "john_doe",
        "email": "john@example.com",
        "createdAt": "2023-01-01T00:00:00Z",
        "updatedAt": "2023-01-02T12:00:00Z",
        "profile": {"firstName": "John", "lastName": "Doe", "age": 30},
        "permissions": ["read", "write", "delete"],
        "settings": {"theme": "dark", "notifications": true}
    }"""
    let result = jsonAs(json, UserRecord)
    doAssert result.userId == 1
    doAssert result.username == "john_doe"
    doAssert result.email == "john@example.com"
    doAssert result.profile["firstName"].getStr() == "John"
    doAssert result.permissions == @["read", "write", "delete"]
    doAssert result.settings["theme"].getStr() == "dark"

# Graph Structures
echo "\n=== Graph Structures ==="

type
    GraphNode = ref object
        id: int
        label: string
        neighbors: seq[GraphNode]
        properties: Table[string, JsonNode]

test "graph node structure":
    let json = """{
        "id": 1,
        "label": "Node A",
        "neighbors": [
            {
                "id": 2,
                "label": "Node B",
                "neighbors": [],
                "properties": {}
            }
        ],
        "properties": {"weight": 1.5, "color": "red"}
    }"""
    let result = jsonAs(json, GraphNode)
    doAssert result.id == 1
    doAssert result.label == "Node A"
    doAssert result.neighbors.len == 1
    doAssert result.neighbors[0].id == 2
    doAssert result.properties["weight"].getFloat() == 1.5

# Advanced Error Cases
echo "\n=== Advanced Error Cases ==="

test "deeply nested malformed JSON":
    let json = """{"a": {"b": {"c": {"d": {"e": "unclosed}}}"""
    try:
        discard jsonAs(json, JsonNode)
        doAssert false, "Should have thrown"
    except ValueError:
        discard

test "array with trailing comma":
    let json = "[1, 2, 3,]"
    let result = jsonAs(json, seq[int])
    doAssert result == @[1, 2, 3]

test "object with trailing comma":
    let json = """{"a": 1, "b": 2,}"""
    let result = jsonAs(json, Table[string, int])
    doAssert result.len == 2
    doAssert result["a"] == 1

# Mixed Static and Dynamic in Complex Scenarios
echo "\n=== Mixed Static/Dynamic Complex Scenarios ==="

type
    HybridSystemConfig = object
        staticName: StaticString[64]
        dynamicConfig: JsonNode
        staticSettings: StaticTable[10, StaticString[32], int]
        dynamicSettings: Table[string, JsonNode]
        staticData: StaticSeq[100, float]
        dynamicData: seq[JsonNode]

test "complex hybrid configuration":
    let json = """{
        "staticName": "SystemConfig",
        "dynamicConfig": {
            "database": {"url": "localhost", "port": 5432},
            "cache": {"enabled": true, "size": 1024}
        },
        "staticSettings": {"max_connections": 100, "timeout": 30},
        "dynamicSettings": {
            "features": ["auth", "logging", "metrics"],
            "limits": {"users": 1000, "requests": 10000}
        },
        "staticData": [1.1, 2.2, 3.3],
        "dynamicData": [{"type": "event", "data": {"value": 42}}]
    }"""
    let result = jsonAs(json, HybridSystemConfig)
    doAssert result.staticName == "SystemConfig"
    doAssert result.dynamicConfig["database"]["port"].getInt() == 5432
    doAssert result.dynamicSettings["features"][0].getStr() == "auth"

# Final Comprehensive Test
echo "\n=== Final Comprehensive Test ==="

type
    ComprehensiveTest = object
        basicTypes: BasicTypes
        collections: Collections  
        nested: NestedStructures
        optional: OptionalFields
        custom: CustomTypes
    
    BasicTypes = object
        intVal: int
        floatVal: float
        stringVal: string
        boolVal: bool
        charVal: char
    
    Collections = object
        intList: seq[int]
        stringList: seq[string]
        intMap: Table[string, int]
        stringMap: Table[string, string]
        mixedList: seq[JsonNode]
    
    NestedStructures = object
        person: Person
        address: Address
        complex: ComplexData
    
    CustomTypes = object
        staticString: StaticString[32]
        staticSeq: StaticSeq[10, int]
        staticTable: StaticTable[5, StaticString[16], int]

test "comprehensive all-features test":
    let json = """{
        "basicTypes": {
            "intVal": 42,
            "floatVal": 3.14159,
            "stringVal": "hello world",
            "boolVal": true,
            "charVal": "X"
        },
        "collections": {
            "intList": [1, 2, 3, 4, 5],
            "stringList": ["a", "b", "c"],
            "intMap": {"one": 1, "two": 2, "three": 3},
            "stringMap": {"key1": "value1", "key2": "value2"},
            "mixedList": [1, "string", true, null, {"nested": "object"}]
        },
        "nested": {
            "person": {
                "name": "Alice",
                "age": 30,
                "active": true
            },
            "address": {
                "street": "123 Main St",
                "city": "Metropolis"
            },
            "complex": {
                "id": 1,
                "tags": ["tag1", "tag2"],
                "metadata": {"version": "1.0"}
            }
        },
        "optional": {
            "required": "present"
        },
        "custom": {
            "staticString": "test",
            "staticSeq": [10, 20, 30],
            "staticTable": {"key1": 100, "key2": 200}
        }
    }"""
    
    let result = jsonAs(json, ComprehensiveTest)
    
    # Basic types
    doAssert result.basicTypes.intVal == 42
    doAssert abs(result.basicTypes.floatVal - 3.14159) < 0.001
    doAssert result.basicTypes.stringVal == "hello world"
    doAssert result.basicTypes.boolVal == true
    doAssert result.basicTypes.charVal == 'X'
    
    # Collections
    doAssert result.collections.intList == @[1, 2, 3, 4, 5]
    doAssert result.collections.stringList == @["a", "b", "c"]
    doAssert result.collections.intMap["one"] == 1
    doAssert result.collections.stringMap["key2"] == "value2"
    doAssert result.collections.mixedList.len == 5
    
    # Nested structures
    doAssert result.nested.person.name == "Alice"
    doAssert result.nested.address.street == "123 Main St"
    doAssert result.nested.complex.tags[0] == "tag1"
    
    # Optional fields
    doAssert result.optional.required == "present"
    
    # Custom types
    doAssert result.custom.staticString == "test"
    doAssert result.custom.staticSeq.len == 3
    var lookup: Table[StaticString[16], int]
    doAssert result.custom.staticTable.get("key1".toStatic[:16], lookup) == 100
    
    # Round-trip verification
    let roundTripJson = jsonDump(result)
    let roundTripResult = jsonAs(roundTripJson, ComprehensiveTest)
    doAssert roundTripResult.basicTypes.intVal == result.basicTypes.intVal
    doAssert roundTripResult.basicTypes.stringVal == result.basicTypes.stringVal
    doAssert roundTripResult.collections.intList == result.collections.intList

# Update the summary section at the end
echo "\n" & "=".repeat(60)
echo fmt"Tests Passed: {testsPassed}"
echo fmt"Tests Failed: {testsFailed}"
echo fmt"Total Tests: {testsPassed + testsFailed}"
echo fmt"Test Coverage: {float(testsPassed) / float(testsPassed + testsFailed) * 100:.1f}%"
if testsFailed == 0:
    echo "🎉 All tests passed! ✓"
    echo "✨ JSON implementation is robust and handles edge cases well!"
else:
    echo fmt"❌ Some tests failed! ({testsFailed} failures)"
    quit(1)

