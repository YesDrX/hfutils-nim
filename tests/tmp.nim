# import hfutils_nim/json

# let data = """
# {
#     "name": "John Doe",
#     "age": 30,
#     "address": {
#         "street": "123 Main St",
#         "city": "Anytown",
#         "state": "CA"
#     }
# }
# """

# type
#     Address = object
#         street: int
#         city: string
    
#     Person = object
#         name: string
#         age: int
#         address: Address

# echo data.jsonAs(Person)