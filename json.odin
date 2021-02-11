package json

import "json:values"
import "json:read"

Object :: values.Object;
Array :: values.Array;
String :: values.String;
Number :: values.Number;
Bool :: values.Bool;

Value :: values.Value;

read_from_path :: read.read_from_path;
read_from_string :: read.read_from_string;
