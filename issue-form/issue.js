var issueForm = {
	components: [
		{
			type: 'textfield',
			key: 'title',
			label: 'Issue title',
			placeholder: 'Enter title here',
			input: true,
			validate: {
				required: true
			}
		},
		{
			inputType: 'radio',
			key: 'not_duplicate',
			label: "I confirm this is not a duplicate issue to the best of my knowledge.",
			input: true,
			values: [
				{value: 'yes', label: 'Yes'},
				{value: 'no', label: "No"}
			],
			validate: {
				required: true,
				pattern: '^yes$'
			},
			type: 'radio',
		},
		{
			inputType: 'radio',
			key: 'issue_type',
			label: 'Type of issue',
			input: true,
			values: [
			{value: 'api_bug', label: 'API not behaving as documented'},
			{value: 'build_bug', label: 'Build issue'},
			{value: 'feature_request', label: 'Feature request'},
			{value: 'documentation_request', label: 'Documentation request'}
			],
			description: 'Need help using audio_service instead? Please ask on StackOverflow via the <a href="https://stackoverflow.com/questions/tagged/audio-service">audio_service tag</a>.',
			validate: {
				required: true
			},
			type: 'radio'
		},
		// api_bug
		{
			type: 'textarea',
			key: 'api_quote',
			label: 'Copy and paste the sentence(s) from the API documentation that isn\'t working correctly',
			placeholder: 'Insert quote here',
			input: true,
			validate: {
				required: true
			},
			description: 'Note: the API documentation is <a href="https://pub.dev/documentation/audio_service/latest/audio_service/audio_service-library.html">here</a>. You may consider submitting a documentation request or a feature request instead if the documentation isn\'t clear or your feature isn\'t supported.',
			// conditional: {
			// 	json: {
			// 		'or': [
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] },
			// 		]
			// 	}
			// }
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'api_bug'
			}
		},
		{
			type: 'textarea',
			key: 'api_actual_behavior',
			label: 'What happened instead of the correct/documented behaviour?',
			input: true,
			validate: {
				required: true
			},
			description: '',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'api_bug'
			}
			// conditional: {
			// 	json: {
			// 		'or': [
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] },
			// 		]
			// 	}
			// }
			// conditional: {
			// 	show: 'true',
			// 	when: 'issue_type',
			// 	eq: 'api_bug'
			// }
		},
		{
			type: 'textarea',
			key: 'runtime_error',
			label: 'Copy and paste the full error (if any)',
			input: true,
			validate: {
				required: false
			},
			description: '',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'api_bug'
			}
		},
		{
			inputType: 'radio',
			key: 'repro_type',
			label: 'Minimal reproduction project',
			input: true,
			values: [
				{value: 'repro_example', label: 'The bug is reproducible on the official example (without any code modifications)'},
				{value: 'repro_link', label: 'I will provide my own minimal reproduction project'}
			],
			description: 'Have a question instead? Please ask on StackOverflow via the <a href="https://stackoverflow.com/questions/tagged/audio-service">audio_service tag</a>.',
			validate: {
				required: true
			},
			type: 'radio',
			conditional: {
				json: {
					'or': [
						{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
						{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] },
					]
				}
			}
			// conditional: {
			// 	show: 'true',
			// 	when: 'issue_type',
			// 	eq: 'api_bug'
			// }
		},
		{
			type: 'textfield',
			key: 'repro_name',
			label: 'File name of example that reproduces the bug',
			placeholder: 'e.g. main.dart',
			defaultValue: 'main.dart',
			input: true,
			validate: {
				required: true
			},
			description: '',
			conditional: {
				json: {
					'and': [
						{ '==': [ { 'var': 'data.repro_type' }, 'repro_example' ] },
						{ 'or': [
							{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
							{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] }
						] }
					]
				}
			}
		},
		{
			type: 'textfield',
			key: 'repro_link',
			label: 'Link to your minimal reproduction project',
			placeholder: 'URL to the Git repo for your reproduction project',
			input: true,
			validate: {
				required: true
			},
			description: '',
			// conditional: {
			//	 show: 'true',
			//	 when: 'issue_type',
			//	 eq: 'api_bug'
			// }
			conditional: {
				json: {
					'and': [
						{ '==': [ { 'var': 'data.repro_type' }, 'repro_link' ] },
						{ 'or': [
							{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
							{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] }
						] }
					]
				}
			}
		},
		{
			type: 'textarea',
			key: 'repro_steps',
			label: 'After launching the project, what steps should the user perform/click to reproduce the bug?',
			input: true,
			validate: {
				required: true
			},
			placeholder: "1. Click this\n2. Click that\n3. etc.",
			description: '',
			conditional: {
				json: {
					'or': [
						{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] }
					]
				}
			}
		},
		// {
		// 	type: 'textfield',
		// 	key: 'api',
		// 	label: 'Name of the misbehaving API',
		// 	placeholder: 'Write API method or field name here',
		// 	input: true,
		// 	validate: {
		// 		required: true
		// 	},
		// 	description: '',
		// 	conditional: {
		// 		show: 'true',
		// 		when: 'issue_type',
		// 		eq: 'api_bug'
		// 	}
		// },
		// build_bug
		{
			type: 'textfield',
			key: 'build_command',
			label: 'Build command',
			placeholder: 'e.g. flutter run',
			input: true,
			validate: {
				required: true
			},
			conditional: {
				json: {
					'==': [ { 'var': 'data.issue_type' }, 'build_bug' ] 
				}
			}
		},
		{
			type: 'textarea',
			key: 'build_error',
			label: 'Copy and paste the full build error',
			input: true,
			validate: {
				required: true
			},
			description: '',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'build_bug'
			}
			// conditional: {
			// 	json: {
			// 		'or': [
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] },
			// 		]
			// 	}
			// }
			// conditional: {
			// 	show: 'true',
			// 	when: 'issue_type',
			// 	eq: 'api_bug'
			// }
		},
		{
			type: 'textarea',
			key: 'build_comments',
			label: 'Comments',
			input: true,
			validate: {
				required: false
			},
			description: '',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'build_bug'
			}
			// conditional: {
			// 	json: {
			// 		'or': [
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
			// 			{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] },
			// 		]
			// 	}
			// }
			// conditional: {
			// 	show: 'true',
			// 	when: 'issue_type',
			// 	eq: 'api_bug'
			// }
		},
		// both api_bug and build_bug
		{
			type: 'textarea',
			key: 'flutter_doctor',
			label: 'Copy and paste the output of <code>flutter doctor</code>',
			input: true,
			validate: {
				required: true
			},
			description: '',
			conditional: {
				json: {
					'or': [
						{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
						{ '==': [ { 'var': 'data.issue_type' }, 'build_bug' ] },
					]
				}
			}
		},
		{
			type: 'textarea',
			key: 'devices',
			label: 'On which device(s) and OS versions did you encounter the bug',
			input: true,
			validate: {
				required: true
			},
			description: '',
			conditional: {
				json: {
					'or': [
						{ '==': [ { 'var': 'data.issue_type' }, 'api_bug' ] },
					]
				}
			}
		},
		// feature_request
		// - confirm reading the documentation
		{
			inputType: 'radio',
			key: 'did_read_docs',
			label: 'I confirm that I checked the API documentation and this feature does not already exist.',
			input: true,
			values: [
				{value: 'yes', label: 'Yes'},
				{value: 'no', label: 'No'}
			],
			description: "Note: If you're not sure if the feature is supported and are just looking for help or support, please ask on StackOverflow for community support.",
			validate: {
				required: true,
				pattern: '^yes$'
			},
			type: 'radio',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'feature_request'
			}
		},
		{
			type: 'textarea',
			key: 'feature_proposal',
			label: 'Describe your feature proposal',
			input: true,
			validate: {
				required: true,
			},
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'feature_request'
			}
		},
		{
			type: 'textarea',
			key: 'feature_use_case',
			label: 'Describe the motivating use case(s) for your feature',
			description: 'Note: "Feature completeness" does not justify adding a feature as much as having a real use case and need for a feature.',
			input: true,
			validate: {
				required: true,
			},
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'feature_request'
			}
		},
		// documentation request
		{
			type: 'textarea',
			key: 'doc_url',
			label: 'To which page(s) does your documentation request apply?',
			placeholder: "URL 1\nURL 2...",
			input: true,
			validate: {
				required: true,
				pattern: '.*http.*'
			},
			description: '',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'documentation_request'
			}
		},
		{
			type: 'textarea',
			key: 'doc_quote',
			label: 'Quote the section(s) you are proposing to change (or leave blank if you are proposing a new section)',
			input: true,
			validate: {
				required: false
			},
			description: 'Copy and paste the text into the box above.',
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'documentation_request'
			}
		},
		{
			type: 'textarea',
			key: 'doc_suggestion',
			label: 'Describe your suggestion',
			input: true,
			validate: {
				required: true
			},
			conditional: {
				show: 'true',
				when: 'issue_type',
				eq: 'documentation_request'
			}
		},
		// {
		// 	inputType: 'checkbox',
		// 	key: 'did_read_doc',
		// 	label: 'I have already checked the API documentation and this feature does not already exist.',
		// 	input: true,
		// 	validate: {
		// 		required: true,
		// 		errorLabel: 'Foo',
		// 		label: 'Bar',
		// 		error: 'Baz'
		// 	},
		// 	type: 'checkbox',
		// 	conditional: {
		// 		show: 'true',
		// 		when: 'issue_type',
		// 		eq: 'feature_request'
		// 	}
		// },

		// {
		// type: "select",
		// label: "Favorite Things",
		// key: "favoriteThings",
		// data: {
		// values: [
		// {
		// value: "raindropsOnRoses",
		// label: "Raindrops on roses"
		// },
		// {
		// value: "whiskersOnKittens",
		// label: "Whiskers on Kittens"
		// },
		// {
		// value: "brightCopperKettles",
		// label: "Bright Copper Kettles"
		// },
		// {
		// value: "warmWoolenMittens",
		// label: "Warm Woolen Mittens"
		// }
		// ]
		// },
		// dataSrc: "values",
		// template: "<span>{{ item.label }}</span>",
		// multiple: true,
		// input: true
		// },
		{
			type: 'button',
			action: 'submit',
			label: 'Submit',
			description: 'You may edit your GitHub issue on the following page.',
			theme: 'primary'
		}
	]
};
