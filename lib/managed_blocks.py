"""Private byte-level managed block framing shared by real instruction writers."""
BEGIN = b'<!-- spec-driven-guardrails: begin -->'
END = b'<!-- spec-driven-guardrails: end -->'

class Conflict(Exception):
    pass

def framed(payload):
    return BEGIN + b'\n' + payload + END

def block(data, begin, end, name):
    if not data.count(begin) and not data.count(end): return None
    if data.count(begin) != 1 or data.count(end) != 1:
        raise Conflict(name + ': duplicate/unmatched/nested managed markers')
    start = data.index(begin); stop = data.index(end)
    if stop < start or (start and data[start-1:start] != b'\n'):
        raise Conflict(name + ': malformed managed markers')
    stop += len(end)
    if data[stop:stop+1] not in (b'', b'\n', b'\r'):
        raise Conflict(name + ': malformed managed markers')
    return start, stop

def managed(data, span, payload):
    if span:
        return data[:span[0]] + payload + data[span[1]:]
    return data + (b'\n' if data and not data.endswith(b'\n') else b'') + payload + b'\n'

