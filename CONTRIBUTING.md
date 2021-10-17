# Contributing to audio_service

Thank you for your interest in contributing!

Contributors not only contribute code but also help by submitting issues, contributing to issue discussions and helping to answer questions on StackOverflow.

This document outlines the rules and procedures when contributing.

## How we use GitHub

We use GitHub as a place and tool for contributors to work together on project development. That is, we use it to report bugs, suggest improvements, and contribute code and documentation to address those bugs or suggestions. It is not used as the place to ask for help (For that we use StackOverflow via the [audio-service](https://stackoverflow.com/questions/tagged/audio-service) tag).

## Reporting a bug

1. **Is it a bug?** Check first that you're using the API correctly according to the documentation (README and API documentation). If the API crashes when used incorrectly, you should not report a bug.
2. **Is it a new bug?** Search the GitHub issues page for bugs. If this bug has already been reported, you should not report a new bug.
3. **How can we reproduce it?** Fork this repository and make the "minimal" changes necessary to the example to reproduce the bug. This step is unnecessary if you choose to fix the bug yourself, or if the example already exhibits the bug without modification.
4. **Submit a report!** With all of the information you have collected you can submit a bug report via the "New issue" page on GitHub. It is necessary to fill in all required information provided by the template in the same format as the template to avoid automatic closure of the issue.

Things to AVOID:

* Do not share your whole app as the minimal reproduction project. This is not "minimal" and it makes it difficult to understand what's happening.
* Do not use a bug report to ask a question. Use StackOverflow instead.
* Do not submit a bug report if you are not using the APIs correctly according to the documentation.
* Try to avoid posting a duplicate bug.
* Do not ignore the formatting requirements and instructions within the issue template.

## Suggesting an improvement

The GitHub "New issue" page provides 2 templates for suggesting improvements: Feature requests and Documentation requests. In both cases, make sure you search existing issues to prevent yourself from posting a duplicate, and ensure that you fill in all required sections in the issue template keeping the original formatting to avoid automatic closure.

## Making a pull request

Pull requests are used to contribute bug fixes, new features or documentation improvements. Before working on a pull request, an issue should exist that describes the feature or bug.

To start a pull request, you first create a fork of this repository, create a new branch, commit and push your code to it.

You should branch your pull request off the `major` branch if it introduces breaking change that is not backwards compatible, or instead off the `minor` branch if it constitutes a non-breaking change or bug fix.

After making your changes, run `flutter analyze` to ensure your code meets the static analysis requirements, and run `flutter test` to ensure all unit tests continue to work. Where appropriate, update any documentation related to your code change.

If you contribute either a feature or a bug fix involving Dart code, we would appreciate a new matching unit test in `audio_service/test`. In the case of a bug fix, the ideal unit test is one that would have failed before your fix and succeeds after your fix.

Add a description of your feature or bug fix to `CHANGELOG.md` under the top section representing the next release. The format for a CHANGELOG entry is:

```
* DESCRIPTION OF YOUR CHANGE... (@your-git-username)
```

Finally create the pull request via [GitHub's instructions](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork) and [link](https://docs.github.com/en/github/managing-your-work-on-github/linking-a-pull-request-to-an-issue) that pull request with the original issue.

Best practices for a pull request:

* You should try to make your pull request diff reflect only the lines of code that needed to be changed to address the issue at hand. If your diff also changes other things, such as by making superficial changes to code formatting and layout, or checking in superfluous files such as your IDE or other config files, please remove them so that your diff focus on the essential. That helps keep the code clean and also makes your pull request easier to review.
* Try not to introduce multiple unrelated changes in a single pull request. Create individual pull requests so that they can be evaluated and accepted independently.
* Use meaningful commit messages so that your changes can be more easily browsed and referenced.
