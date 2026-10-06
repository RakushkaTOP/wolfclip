"""Russian when the system language is Russian, English otherwise."""

import os


def _detect_russian() -> bool:
    forced = os.environ.get("WOLFCLIP_LANG")
    if forced:
        return forced.lower().startswith("ru")
    for var in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(var)
        if value:
            return value.lower().startswith("ru")
    return False


IS_RU = _detect_russian()


def tr(ru: str, en: str) -> str:
    return ru if IS_RU else en


def plural(n: int, ru: tuple[str, str, str], en: tuple[str, str]) -> str:
    if IS_RU:
        m10, m100 = n % 10, n % 100
        if m10 == 1 and m100 != 11:
            word = ru[0]
        elif 2 <= m10 <= 4 and not 12 <= m100 <= 14:
            word = ru[1]
        else:
            word = ru[2]
    else:
        word = en[0] if n == 1 else en[1]
    return f"{n} {word}"
