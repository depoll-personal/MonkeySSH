"""Regression coverage for skipped jobs, native inputs, and shallow diffs."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import ci_changes as changes


class ClassificationTest(unittest.TestCase):
    def assert_platforms(self, paths, platforms):
        result = changes.classify(paths)
        self.assertEqual({p for p in changes.PLATFORMS if result[p]}, set(platforms))
        return result

    def test_documentation_is_a_noop(self):
        self.assertFalse(any(changes.classify(['README.md', 'docs/setup.md']).values()))

    def test_dart_changes_keep_analyzer_and_tests_without_native_builds(self):
        for path in ['lib/main.dart', 'test/widget/example_test.dart', 'analysis_options.yaml']:
            with self.subTest(path=path):
                result = self.assert_platforms([path], [])
                self.assertTrue(result['run_check'])

    def test_release_and_workflow_tooling_do_not_require_flutter(self):
        for path in [
            '.github/workflows/security.yml', '.github/actions/deployment-status/action.yml',
            '.github/dependabot.yml', 'scripts/validate_app_store_metadata.py',
            'scripts/generate_store_screenshots.py', 'test/scripts/preview_release_notes_test.rb',
            'Gemfile.lock', 'ios/fastlane/Fastfile',
            'ios/fastlane/metadata-production/en-US/description.txt',
            'android/fastlane/metadata-private/android/en-US/title.txt',
        ]:
            with self.subTest(path=path):
                result = self.assert_platforms([path], [])
                self.assertTrue(result['tooling'])
                self.assertFalse(result['run_check'])

    def test_each_native_platform_is_checked_in_isolation(self):
        for platform in changes.PLATFORMS:
            with self.subTest(platform=platform):
                result = self.assert_platforms([f'{platform}/native/source'], [platform])
                self.assertTrue(result['run_check'])

    def test_shared_dependencies_assets_and_ci_changes_build_every_platform(self):
        for path in [
            'pubspec.yaml', 'pubspec.lock', 'assets/version_codenames.json',
            '.github/workflows/ci.yml', 'scripts/ci_changes.py',
            'scripts/cache_sqlite3_native_assets.sh',
            'third_party/permission_handler_apple/ios/Package.swift',
            'third_party/in_app_purchase_android/android/build.gradle',
        ]:
            with self.subTest(path=path):
                result = self.assert_platforms([path], changes.PLATFORMS)
                self.assertTrue(result['run_check'])

    def test_helper_inputs_also_run_go_tests(self):
        for path in [*changes.PAYLOAD_SCRIPTS, 'remote/monkeymux/go.mod',
                     'remote/monkeymux/conpty/ConPTY.dll', 'remote/monkeymux/main.go']:
            with self.subTest(path=path):
                result = self.assert_platforms([path], changes.PLATFORMS)
                self.assertTrue(result['go'])

    def test_vendored_terminal_inputs_keep_test_coverage(self):
        for path in ['third_party/xterm/pubspec.yaml', 'third_party/xterm/pubspec.lock',
                     'third_party/xterm/lib/src/terminal.dart']:
            self.assertTrue(changes.classify([path])['run_check'])


class GitDiffTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.git('init', '-q')
        self.git('config', 'user.email', 'ci-test@example.invalid')
        self.git('config', 'user.name', 'CI test')
        self.write('android/old.cpp', 'old source')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def write(self, path, text):
        dest = self.root / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)

    def classify(self, event='pull_request', base=None):
        output = self.root / 'output'
        output.write_text('')
        env = {
            **os.environ, 'EVENT_NAME': event,
            'PR_BASE_SHA': base or self.base, 'MG_BASE_SHA': base or self.base,
            'PUSH_BEFORE_SHA': base or self.base, 'HEAD_SHA': self.git('rev-parse', 'HEAD'),
            'GITHUB_OUTPUT': str(output),
        }
        subprocess.run([sys.executable, str(ROOT / 'scripts/ci_changes.py')],
                       cwd=self.root, env=env, check=True, capture_output=True)
        return dict(line.split('=') for line in output.read_text().splitlines())

    def test_pr_push_and_merge_group_diff_include_both_sides_of_a_rename(self):
        (self.root / 'docs').mkdir()
        self.git('mv', 'android/old.cpp', 'docs/old.cpp')
        self.git('commit', '-qm', 'move')
        for event in ['pull_request', 'merge_group', 'push']:
            with self.subTest(event=event):
                result = self.classify(event)
                self.assertEqual(result['android'], 'true')
                self.assertEqual(result['ios'], 'false')

    def test_nul_separation_prevents_newlines_in_names_from_inventing_paths(self):
        self.write('docs/newline\nlib/fake.dart', 'documentation')
        self.git('add', '.')
        self.git('commit', '-qm', 'newline')
        # It is a .dart path, so analysis is conservative, but it must not
        # invent a native path from the newline inside a single filename.
        result = self.classify()
        self.assertEqual(result['android'], 'false')
        self.assertEqual(result['go'], 'false')

    def test_missing_shallow_base_and_first_push_fail_open(self):
        for base in ['0' * 40, 'f' * 40]:
            self.assertEqual(set(self.classify('push', base).values()), {'true'})

    def test_empty_diff_skips_every_job(self):
        self.assertEqual(set(self.classify().values()), {'false'})


class WorkflowContractsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        script = "require 'yaml'; require 'json'; puts JSON.generate(ARGV.to_h { |f| [File.basename(f), YAML.load_file(f)] })"
        cls.workflows = json.loads(subprocess.check_output(
            ['ruby', '-e', script, *map(str, (ROOT / '.github/workflows').glob('*.yml'))],
            text=True,
        ))

    def test_apple_cache_keys_limits_and_save_conditions(self):
        actions = json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e',
            'puts JSON.generate(ARGV.map { |f| YAML.load_file(f) })',
            *[str(ROOT / '.github/actions' / name / 'action.yml')
              for name in ['apple-cache-restore', 'apple-cache-save']]], text=True))
        restore, save = [action['runs']['steps'] for action in actions]
        keyed = {step['id']: step for step in restore if 'id' in step}
        suffix = "${{ runner.os }}-${{ runner.arch }}-${{ steps.toolchain.outputs.xcode }}-${{ inputs.flutter-version }}"
        self.assertEqual(keyed['compilation']['with']['key'], '${{ inputs.platform }}-compile-v1-' + suffix +
                         '-${{ inputs.configuration }}-${{ inputs.dependency-fingerprint }}')
        self.assertEqual(keyed['workspace']['with']['key'], 'spm-workspace-v1-' + suffix +
                         '-${{ inputs.platform }}-${{ inputs.dependency-fingerprint }}')
        spm_key = "spm-${{ runner.os }}-${{ hashFiles('ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved', 'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}"
        self.assertEqual(keyed['swiftpm']['with']['key'], spm_key)
        self.assertEqual(keyed['swiftpm']['with']['restore-keys'], 'spm-${{ runner.os }}-')
        self.assertEqual(save[-1]['with']['key'], spm_key)
        self.assertEqual(restore[1]['run'], 'rm -rf ~/Library/Caches/org.swift.swiftpm/manifests')
        for kind in ['compilation', 'workspace']:
            step = next(step for step in save if step.get('with', {}).get('key') == '${{ inputs.' + kind + '-key }}')
            self.assertEqual(step['if'], "steps.sizes.outputs." + kind + " == 'true' && inputs." + kind + "-hit != 'true'")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'build/ios/SourcePackages').mkdir(parents=True)
            du = root / 'du'
            du.write_text('#!/bin/sh\nprintf "%s\\tcache\\n" "$TEST_CACHE_KIB"\n')
            du.chmod(0o755)
            for limit in [1048576, 2097152]:
                for size in [0, 1, limit, limit + 1]:
                    output = root / 'output'
                    output.write_text('')
                    subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', save[0]['run']],
                                   cwd=root, check=True, env={**os.environ,
                                       'PATH': str(root) + os.pathsep + os.environ['PATH'],
                                       'PLATFORM': 'ios', 'TEST_CACHE_KIB': str(size),
                                       'COMPILATION_LIMIT_KIB': str(limit), 'WORKSPACE_LIMIT_KIB': '2097152',
                                       'GITHUB_OUTPUT': str(output), 'GITHUB_STEP_SUMMARY': str(root / 'summary')})
                    expected = ('compilation=true\n' if 0 < size <= limit else '') + (
                        'workspace=true\n' if 0 < size <= 2097152 else '')
                    self.assertEqual(output.read_text(), expected)
        for workflow, platform, configuration, limit in [('ci.yml', 'ios', 'production', 1048576),
                ('ci.yml', 'macos', 'release', 2097152), ('build-deploy.yml', 'ios', '${{ inputs.flavor }}', 1048576)]:
            steps = self.workflows[workflow]['jobs']['build-' + platform]['steps']
            caches = [step for step in steps if step.get('with', {}).get('phase') == 'build']
            self.assertEqual(caches[0]['with']['configuration'], configuration)
            self.assertEqual(caches[0]['with']['dependency-fingerprint'],
                             "${{ hashFiles('pubspec.lock', '" + platform + "/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}")
            self.assertEqual(caches[1]['with']['compilation-limit-kib'], limit)
            self.assertEqual(caches[1]['with']['workspace-limit-kib'], 2097152)
            for kind in ['compilation', 'workspace']:
                for field in ['key', 'hit']:
                    self.assertEqual(caches[1]['with'][kind + '-' + field], '${{ steps.apple-cache.outputs.' + kind + '-' + field + ' }}')
            if workflow == 'ci.yml':
                self.assertEqual(steps[-1]['if'], "steps.spm-cache.outputs.swiftpm-hit != 'true'")
            else:
                self.assertEqual(caches[0]['if'], "inputs.ios-reuse-ipa-artifact-name == '' && inputs.deploy-ios-to == 'none'")
                self.assertEqual(caches[1]['if'], "steps.apple-cache.outcome == 'success'")
                self.assertFalse(any(step.get('with', {}).get('phase') == 'swiftpm' and
                                     step.get('uses') == './.github/actions/apple-cache-save' for step in steps))

    def test_mobile_triggers_share_all_compile_and_packaging_inputs(self):
        for file, event in [('preview.yml', 'pull_request'), ('deploy-private.yml', 'push'),
                            ('preview-ios.yml', 'pull_request')]:
            with self.subTest(file=file):
                workflow = self.workflows[file]
                triggers = workflow.get('on', workflow.get('true'))
                self.assertEqual(triggers[event]['paths'], changes.MOBILE_PATHS)
                self.assertNotIn('**.dart', triggers[event]['paths'])
                self.assertIn('remote/monkeymux/**', triggers[event]['paths'])
                self.assertIn('third_party/**', triggers[event]['paths'])

    def test_gate_waits_for_independent_tooling_and_terminal_checks(self):
        jobs = self.workflows['ci.yml']['jobs']
        self.assertIn('tooling', jobs['ci']['needs'])
        self.assertIn('terminal-test', jobs['ci']['needs'])
        self.assertEqual(jobs['tooling']['needs'], 'changes')
        self.assertNotIn('monkeymux-assets', jobs['terminal-test']['needs'])

    def test_payload_cache_can_only_be_saved_by_push_to_main_ci(self):
        for filename, workflow in self.workflows.items():
            for job in workflow['jobs'].values():
                for step in job.get('steps', []):
                    if step.get('with', {}).get('path') != 'assets/monkeymux/':
                        continue
                    uses = step.get('uses', '')
                    if uses.startswith('actions/cache/save@'):
                        self.assertEqual(filename, 'ci.yml')
                        self.assertIn("github.event_name == 'push'", step['if'])
                        self.assertIn("github.ref == 'refs/heads/main'", step['if'])
                    self.assertFalse(uses.startswith('actions/cache@'))
                    if uses.startswith('actions/upload-artifact@'):
                        self.assertTrue(step['with']['include-hidden-files'])

    def test_deployment_source_is_an_immutable_commit(self):
        for job in self.workflows['deploy-private.yml']['jobs'].values():
            if 'uses' in job:
                self.assertEqual(job['with']['source-ref'], '${{ github.sha }}')
        for job in self.workflows['build-deploy.yml']['jobs'].values():
            for step in job.get('steps', []):
                if step.get('uses', '').startswith('actions/checkout@'):
                    self.assertNotEqual(step.get('with', {}).get('ref'), '${{ github.ref }}')

    def test_profile_maintenance_supports_both_distribution_types(self):
        workflow = self.workflows['regenerate-ios-profiles.yml']
        triggers = workflow.get('on', workflow.get('true'))
        self.assertEqual(triggers['workflow_dispatch']['inputs']['profile-type']['options'],
                         ['appstore', 'adhoc'])


if __name__ == '__main__':
    unittest.main()
