fn identity<T>(value: T) -> T:
    return value

print(identity(42), identity(true), identity(19) + identity(23))
