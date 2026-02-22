"""Tests for monitor.py."""

import json
import os
import tempfile
import datetime

import pytest

from monitor import sanitize, main


# --- sanitize() ---

def test_sanitize_removes_ansi_color():
    assert sanitize('\x1b[31mRED\x1b[0m') == 'RED'


def test_sanitize_removes_escape_sequence():
    assert sanitize('\x1b]0;evil title\x07') == '0;evil title'


def test_sanitize_removes_control_chars():
    assert sanitize('hello\x00\x07world') == 'helloworld'


def test_sanitize_passes_through_clean_string():
    assert sanitize('google:default') == 'google:default'


def test_sanitize_passes_through_non_string():
    assert sanitize(42) == 42
    assert sanitize(None) is None


# --- main() with fixture files ---

def _write_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f)


def _make_config(primary, fallbacks=None):
    return {
        'agents': {
            'defaults': {
                'model': {
                    'primary': primary,
                    'fallbacks': fallbacks or [],
                }
            }
        }
    }


def _make_auth(usage_stats=None):
    return {'usageStats': usage_stats or {}}


@pytest.fixture()
def tmp_files(tmp_path):
    auth_path = str(tmp_path / 'auth-profiles.json')
    config_path = str(tmp_path / 'openclaw.json')
    return auth_path, config_path


def test_main_ok_status(tmp_files, capsys, monkeypatch):
    auth_path, config_path = tmp_files
    _write_json(config_path, _make_config('google/gemini-flash'))
    _write_json(auth_path, _make_auth({
        'google:default': {'errorCount': 0},
    }))
    monkeypatch.setenv('AUTH_FILE', auth_path)
    monkeypatch.setenv('CONFIG_FILE', config_path)

    main()
    out = capsys.readouterr().out
    assert 'google:default' in out
    assert '[primary]' in out
    assert 'STATUS:     ok' in out


def test_main_cooldown_status(tmp_files, capsys, monkeypatch):
    auth_path, config_path = tmp_files
    future_ms = (datetime.datetime.now().timestamp() + 300) * 1000
    _write_json(config_path, _make_config('google/gemini-flash'))
    _write_json(auth_path, _make_auth({
        'google:default': {'errorCount': 3, 'cooldownUntil': future_ms},
    }))
    monkeypatch.setenv('AUTH_FILE', auth_path)
    monkeypatch.setenv('CONFIG_FILE', config_path)

    main()
    out = capsys.readouterr().out
    assert 'COOLDOWN' in out


def test_main_disabled_status(tmp_files, capsys, monkeypatch):
    auth_path, config_path = tmp_files
    future_ms = (datetime.datetime.now().timestamp() + 600) * 1000
    _write_json(config_path, _make_config('google/gemini-flash'))
    _write_json(auth_path, _make_auth({
        'google:default': {'errorCount': 5, 'disabledUntil': future_ms},
    }))
    monkeypatch.setenv('AUTH_FILE', auth_path)
    monkeypatch.setenv('CONFIG_FILE', config_path)

    main()
    out = capsys.readouterr().out
    assert 'DISABLED' in out


def test_main_fallback_labels(tmp_files, capsys, monkeypatch):
    auth_path, config_path = tmp_files
    _write_json(config_path, _make_config(
        'google/gemini-flash',
        fallbacks=['openai/gpt-4o', 'anthropic/claude-haiku-4-5'],
    ))
    _write_json(auth_path, _make_auth({}))
    monkeypatch.setenv('AUTH_FILE', auth_path)
    monkeypatch.setenv('CONFIG_FILE', config_path)

    main()
    out = capsys.readouterr().out
    assert '[primary]' in out
    assert '[fallback#1]' in out
    assert '[fallback#2]' in out
    assert 'no failover data' in out


def test_main_missing_auth_file(tmp_files, monkeypatch):
    auth_path, config_path = tmp_files
    _write_json(config_path, _make_config('google/gemini-flash'))
    monkeypatch.setenv('AUTH_FILE', auth_path)
    monkeypatch.setenv('CONFIG_FILE', config_path)

    with pytest.raises(SystemExit, match='1'):
        main()


def test_main_invalid_json(tmp_files, monkeypatch):
    auth_path, config_path = tmp_files
    _write_json(config_path, _make_config('google/gemini-flash'))
    with open(auth_path, 'w') as f:
        f.write('{broken')
    monkeypatch.setenv('AUTH_FILE', auth_path)
    monkeypatch.setenv('CONFIG_FILE', config_path)

    with pytest.raises(SystemExit, match='1'):
        main()
