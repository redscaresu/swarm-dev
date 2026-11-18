"""clock.py — the one clock bin/lib's Python reads for now and today. SWARM_DASH_NOW (epoch seconds)
fixes it, so a test's today holds across midnight and dash, flow and the reports it runs agree on the
day. scripts/lint (make check) fails a date.today(), datetime.today(), datetime.now() or
datetime.utcnow() anywhere else in bin/lib/*.py. time.time() is left to the deadlines and ages that
must run on the real clock."""
import datetime, os, time


def now():
    """Epoch seconds: SWARM_DASH_NOW when it is set, else the real clock."""
    return float(os.environ.get("SWARM_DASH_NOW") or time.time())


def today():
    """The local day of now()."""
    return datetime.date.fromtimestamp(now())


def utc_now():
    """now() as an aware datetime in UTC."""
    return datetime.datetime.fromtimestamp(now(), datetime.timezone.utc)
