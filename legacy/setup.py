from setuptools import setup

APP = ['web_app.py']
DATA_FILES = [
    ('templates', ['templates/index.html']),
    ('lib', [
        '/Users/ilan/miniconda3/lib/libffi.8.dylib',
        '/Users/ilan/miniconda3/lib/libssl.3.dylib',
        '/Users/ilan/miniconda3/lib/libcrypto.3.dylib',
    ]),
]
OPTIONS = {
    'argv_emulation': True,
    'iconfile': "PL_icon.icns",
    'packages': ['flask', 'werkzeug', 'jinja2', 'cffi'],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
