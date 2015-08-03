import sys
import re
from cpython cimport bool


class BuxomError(Exception):

    '''Base exception class for Buxom'''


class SchemaError(BuxomError):

    '''Exception for errors encountered while defining schema'''


class Invalid(BuxomError):

    '''Exception when schema is violated'''


class MultipleInvalid(BuxomError):

    '''Exception when multiple fields violate schema'''


class BaseValidator(object):

    '''A BaseValidator is the basic building block of schema and keywrapper objects'''

    def __init__(self, *args, **kwargs):
        pass

    def validate(self, dict data, *args, **kwargs):
        raise NotImplementedError


class KeyWrapper(BaseValidator):

    '''A KeyWrapper is an object that wraps around a dictionary key to provide
    additional semantics (example: Required, Optional)
    '''

    def __init__(self, key):
        self._key = self._get_key(key)

    @staticmethod
    def _get_key(key):
        if isinstance(key, KeyWrapper):
            return KeyWrapper._get_key(key._key)
        else:
            return key

    def __repr__(self):
        return KeyWrapper._get_key(self._key)


class Required(KeyWrapper):

    '''A KeyWrapper that raises an error if the required key isn't present in the dict'''

    def __init__(self, key):
        super(Required, self).__init__(key)

    def validate(self, dict data, *args, **kwargs):
        if self._key not in data:
            raise Invalid('Required key {} not found in data'.format(self._key))
        return data


class Optional(KeyWrapper):

    '''A KeyWrapper that allows a key to not be present'''

    def __init__(self, key):
        super(Optional, self).__init__(key)

    def validate(self, dict data, *args, **kwargs):
        return data


class Schema(BaseValidator):

    '''A schema is a (potentially nested) map-like structure that enforces data integrity'''

    def __init__(self, dict schema, bool extra=False):
        self._schema = schema
        self._extra = extra

    def validate(self, dict data, bool partial=False, bool suppress_exception=False):
        '''Validate data against schema
        If partial is False, only keys present in data are validated,
        and required keys are ignored even if they aren't present
        '''
        if self._extra:
            data_keys = set(data.keys())
            schema_keys = set((KeyWrapper._get_key(key) for key in schema.keys()))
            if not data_keys == schema_keys:
                raise Invalid('The following keys were not found in data: {}'.format(', '.join(schema_keys - data_keys)))

        schema = self._schema
        try:
            for key in schema:
                actual_key = KeyWrapper._get_key(key)
                if isinstance(key, KeyWrapper):
                    key.validate(data)

                if isinstance(schema[key], Schema):
                    if actual_key in data:
                        data[actual_key] = schema[key].validate({actual_key: data[actual_key]}, suppress_exception)[actual_key]
                else:
                    if actual_key in data and not isinstance(data[actual_key], schema[key]):
                        raise Invalid('data[{}] is not an instance of type {}'.format(actual_key, schema[key]))
        except Invalid:
            if suppress_exception:
                return False
            else:
                raise

        return data


class AnyAll(Schema):

    def __init__(self, *args, **kwargs):
        self._types = args
        self._validate_function = None

    def validate(self, dict data, *args, **kwargs):
        key = data.keys()[0]
        for key in data.keys():
            if isinstance(data[key], Schema):
                data[key] = data[key].validate({key: data[key]})
            else:
                if not self._validate_function(isinstance(data[key], t) for t in self._types if not isinstance(t, Schema)):
                    raise Invalid('data[{}] is not in types {}'.format([t for t in self._types if not isinstance(t, Schema)]))

        return {key: data[key]}


class Any(AnyAll):

    def __init__(self, *args, **kwargs):
        super(AnyAll, self).__init__(*args, **kwargs)
        self._validate_function = any


class All(AnyAll):

    def __init__(self, *args, **kwargs):
        super(AnyAll, self).__init__(*args, **kwargs)
        self._validate_function = all


class Callable(Schema):

    def __init__(self, callable, *args, **kwargs):
        self._args = args
        self._kwargs = kwargs
        self._callable = callable

    def validate(self, dict data):
        for key in data:
            if isinstance(data[key], Schema):
                data[key] = data[key].validate({key: data[key]})
            else:
                data[key] = self._callable(data[key])


class Coerce(Callable):

    def __init__(self, type):
        self._callable = type


class Length(Schema):

    def __init__(self, long min_len=0, long max_len=sys.maxint):
        self._min = min_len
        self._max = max_len

    def validate(self, dict data):
        for key in data:
            if isinstance(data[key], Schema):
                data[key] = data[key].validate({key: data[key]})
            else:
                if len(data[key]) >= self._min and len(data[key]) <= self._max:
                    data[key] = data[key]
                else:
                    raise Invalid


class Range(Schema):

    def __init__(self, long start, long stop=None, long step=None):
        self._start = start
        self._stop = stop
        self._step = step

    def validate(self, dict data):
        for key in data:
            if isinstance(data[key], Schema):
                data[key] = data[key].validate({key: data[key]})
            else:
                if data[key] in set(range(self._start, self._stop, self._step)):
                    data[key] = data[key]
                else:
                    raise Invalid
