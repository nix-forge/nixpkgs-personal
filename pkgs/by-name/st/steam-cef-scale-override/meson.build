project(
  'steam-cef-scale-override',
  'c',
  version: '1.0.0',
  meson_version: '>=1.8.0',
  default_options: [
    'b_ndebug=true',
    'c_std=c11',
    'optimization=2',
    'warning_level=3',
    'werror=true',
  ],
)

cc = meson.get_compiler('c')
strict_c_args = cc.get_supported_arguments(
  '-Wconversion',
  '-Wformat=2',
  '-Wmissing-prototypes',
  '-Wshadow',
  '-Wsign-conversion',
  '-Wstrict-prototypes',
)
hardening_link_args = cc.get_supported_link_arguments(
  '-Wl,-z,noexecstack',
  '-Wl,-z,now',
  '-Wl,-z,relro',
)

sanitizers_enabled = get_option('b_sanitize') != 'none'
if sanitizers_enabled
  add_project_arguments(
    cc.get_supported_arguments(
      '-fno-omit-frame-pointer',
      '-fno-sanitize-recover=all',
    ),
    language: 'c',
  )
  add_project_link_arguments(
    cc.get_supported_link_arguments('-fno-sanitize-recover=all'),
    language: 'c',
  )
endif

dl_dependency = cc.find_library('dl', required: true)
math_dependency = cc.find_library('m', required: true)

shim = shared_library(
  'steam-cef-scale-override',
  'steam-cef-scale-override.c',
  c_args: strict_c_args,
  dependencies: [dl_dependency, math_dependency],
  gnu_symbol_visibility: 'hidden',
  install: true,
  link_args: hardening_link_args,
)

install_data(
  'LICENSE',
  install_dir: get_option('datadir') / 'licenses' / meson.project_name(),
)
install_data(
  'README.md',
  install_dir: get_option('datadir') / 'doc' / meson.project_name(),
)

if get_option('tests')
  mock_cef = shared_library(
    'cef-test',
    'test-libcef.c',
    c_args: strict_c_args,
  )

  helper_link_targets = [mock_cef]
  preload = shim.full_path()
  if sanitizers_enabled
    # Linking the shim first loads the sanitizer runtime before the mock CEF
    # library. b_asneeded is disabled for this configuration by the Nix check.
    helper_link_targets = [shim, mock_cef]
    preload = ''
  endif

  helper = executable(
    'steamwebhelper',
    'test-helper.c',
    c_args: strict_c_args,
    link_with: helper_link_targets,
  )

  test_environment = environment()
  if sanitizers_enabled
    test_environment.set('ASAN_OPTIONS', 'halt_on_error=1:exitcode=99:detect_leaks=1')
    test_environment.set(
      'UBSAN_OPTIONS',
      'halt_on_error=1:exitcode=99:print_stacktrace=1',
    )
  endif

  test(
    'CEF interposition behavior',
    find_program('bash'),
    args: [
      files('check-mock.sh'),
      meson.current_build_dir(),
      preload,
    ],
    depends: [shim, mock_cef, helper],
    env: test_environment,
    timeout: 30,
  )
endif
