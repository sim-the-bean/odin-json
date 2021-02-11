package values

Object :: distinct map[String]Value;
Array :: distinct [dynamic]Value;
String :: distinct string;
Number :: distinct f64;
Bool :: distinct bool;

// not using #no_nil, cause `null` is a valid json value
Value :: union{Object, Array, String, Number, Bool};
