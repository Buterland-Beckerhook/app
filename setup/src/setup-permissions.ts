/**
 * Directus Permissions & Token Setup
 * - Creates a static token for the admin user
 * - Sets up public read access for all content collections
 * - Creates the "Kalender" role and "Kalender-Bearbeiter" policy with
 *   restricted event permissions (users are created separately as needed)
 *
 * Usage:
 *   npx tsx src/setup-permissions.ts
 *
 * Environment:
 *   DIRECTUS_URL            (default: http://localhost:8055)
 *   ADMIN_EMAIL             (default: admin@buterland-beckerhook.de)
 *   ADMIN_PASSWORD          (default: directus)
 *   DIRECTUS_STATIC_TOKEN   (default: dev-static-token-change-in-production)
 */

import {
	readMe,
	updateUser,
	readPolicies,
	createPermission,
	createRole,
	readRoles,
	createPolicy
} from '@directus/sdk';
import { createAdminClient, rawPost, DIRECTUS_URL } from './directus.js';

const STATIC_TOKEN =
	process.env.DIRECTUS_STATIC_TOKEN ?? 'dev-static-token-change-in-production';

async function main(): Promise<void> {
	console.log('=== Directus Permissions & Token Setup ===');
	console.log(`URL: ${DIRECTUS_URL}`);
	console.log('');

	const client = await createAdminClient();
	console.log('Authenticated.');

	// Helper
	async function safeCreatePermission(
		data: Parameters<typeof createPermission>[0]
	): Promise<void> {
		try {
			await client.request(createPermission(data));
			console.log(`  OK: ${data.action} on "${data.collection}"`);
		} catch {
			console.log(`  WARN: ${data.action} on "${data.collection}" may already exist or failed`);
		}
	}

	// =========================================================================
	// 1. Set static token on admin user
	// =========================================================================
	console.log('');
	console.log('--- Setting Static Token ---');

	const me = await client.request(readMe({ fields: ['id', 'email'] }));
	console.log(`Admin user ID: ${me.id}`);

	try {
		await client.request(updateUser(me.id as string, { token: STATIC_TOKEN }));
		console.log(`  OK: static token set`);
	} catch (err) {
		console.log(`  WARN: setting static token failed`);
		if (process.env.DEBUG) console.error(err);
	}

	console.log(`Static token: ${STATIC_TOKEN}`);

	// Verify token works
	process.stdout.write('Verifying static token... ');
	try {
		const verifyRes = await fetch(`${DIRECTUS_URL}/users/me`, {
			headers: { Authorization: `Bearer ${STATIC_TOKEN}` }
		});
		if (verifyRes.ok) {
			const data = (await verifyRes.json()) as { data: { email: string } };
			console.log(data.data.email);
		} else {
			console.log('FAILED');
		}
	} catch {
		console.log('FAILED');
	}

	// =========================================================================
	// 2. Public role permissions (read access to published content)
	// =========================================================================
	console.log('');
	console.log('--- Setting up Public Permissions ---');

	// In Directus 11+, permissions are tied to policies.
	// Find the public (non-admin) policy.
	let publicPolicyId: string | null = null;

	try {
		const policies = await client.request(
			readPolicies({
				fields: ['id', 'name', 'admin_access'],
				limit: -1
			})
		);

		// First try to find a policy with "public" in the name
		for (const p of policies) {
			if (
				p.admin_access === false &&
				typeof p.name === 'string' &&
				p.name.toLowerCase().includes('public')
			) {
				publicPolicyId = p.id as string;
				break;
			}
		}

		// Fallback: first non-admin policy
		if (!publicPolicyId) {
			for (const p of policies) {
				if (p.admin_access === false) {
					publicPolicyId = p.id as string;
					break;
				}
			}
		}
	} catch (err) {
		console.error('Failed to read policies:', err);
	}

	if (!publicPolicyId) {
		console.log(
			'WARNING: Could not find public policy. You may need to set up public permissions manually in the Directus admin UI.'
		);
	} else {
		console.log(`Public policy ID: ${publicPolicyId}`);

		const publicCollections = [
			'articles',
			'article_images',
			'thrones',
			'events',
			'locations',
			'people',
			'pages',
			'directus_files'
		];

		for (const collection of publicCollections) {
			await safeCreatePermission({
				policy: publicPolicyId,
				collection,
				action: 'read',
				fields: ['*'],
				permissions: {},
				validation: {}
			});
		}
	}

	// =========================================================================
	// 3. Calendar role + policy (users are created separately as needed)
	// =========================================================================
	console.log('');
	console.log('--- Creating Calendar Role & Policy ---');

	// 3a. Create "Kalender" role
	let roleId: string | null = null;

	try {
		const role = await client.request(
			createRole({
				name: 'Kalender',
				description: 'Eingeschränkter Zugang: kann interne Termine anlegen und verwalten',
				icon: 'calendar_month'
			})
		);
		roleId = role.id as string;
		console.log(`  OK: created role "Kalender"`);
	} catch {
		console.log('  Role may already exist, looking it up...');
	}

	if (!roleId) {
		const roles = await client.request(readRoles({ fields: ['id', 'name'], limit: -1 }));
		for (const r of roles) {
			if (r.name === 'Kalender') {
				roleId = r.id as string;
				break;
			}
		}
	}

	if (!roleId) {
		console.error('ERROR: Could not create or find "Kalender" role.');
		process.exit(1);
	}

	console.log(`Calendar role ID: ${roleId}`);

	// 3b. Create "Kalender-Bearbeiter" policy
	let calPolicyId: string | null = null;

	try {
		const policy = await client.request(
			createPolicy({
				name: 'Kalender-Bearbeiter',
				description:
					'Kann interne Termine erstellen/bearbeiten, aber nicht öffentlich ankündigen',
				icon: 'edit_calendar',
				admin_access: false,
				app_access: true
			})
		);
		calPolicyId = policy.id as string;
		console.log(`  OK: created policy "Kalender-Bearbeiter"`);
	} catch {
		console.log('  Policy may already exist, looking it up...');
	}

	if (!calPolicyId) {
		const policies = await client.request(
			readPolicies({ fields: ['id', 'name'], limit: -1 })
		);
		for (const p of policies) {
			if (p.name === 'Kalender-Bearbeiter') {
				calPolicyId = p.id as string;
				break;
			}
		}
	}

	if (!calPolicyId) {
		console.error('ERROR: Could not create or find "Kalender-Bearbeiter" policy.');
		process.exit(1);
	}

	console.log(`Calendar policy ID: ${calPolicyId}`);

	// 3c. Attach policy to role (via /access — not covered by SDK)
	console.log('Attaching policy to role...');
	try {
		await rawPost(client, '/access', { role: roleId, policy: calPolicyId });
		console.log('  OK: /access');
	} catch {
		console.log('  WARN: /access may already exist or failed');
	}

	// 3d. Calendar permissions
	console.log('');
	console.log('--- Setting Calendar Permissions ---');

	const eventFields = [
		'title',
		'slug',
		'start',
		'end',
		'body',
		'cancel_reason',
		'status',
		'revision',
		'enable_ical',
		'location',
		'parent',
		'calendar',
		'announce'
	];

	// events: CREATE — announce forced to false
	await safeCreatePermission({
		policy: calPolicyId,
		collection: 'events',
		action: 'create',
		fields: eventFields,
		permissions: {},
		validation: { _and: [{ announce: { _eq: false } }] },
		presets: { announce: false, status: 'published' }
	});

	// events: READ — own events + all publicly announced events
	await safeCreatePermission({
		policy: calPolicyId,
		collection: 'events',
		action: 'read',
		fields: ['*'],
		permissions: {
			_or: [
				{ user_created: { _eq: '$CURRENT_USER' } },
				{ announce: { _eq: true } }
			]
		},
		validation: {}
	});

	// events: UPDATE — only own events, cannot set announce=true
	await safeCreatePermission({
		policy: calPolicyId,
		collection: 'events',
		action: 'update',
		fields: eventFields,
		permissions: { user_created: { _eq: '$CURRENT_USER' } },
		validation: { _and: [{ announce: { _eq: false } }] }
	});

	// events: DELETE — only own events
	await safeCreatePermission({
		policy: calPolicyId,
		collection: 'events',
		action: 'delete',
		fields: ['*'],
		permissions: { user_created: { _eq: '$CURRENT_USER' } },
		validation: {}
	});

	// locations: READ — for the location dropdown
	await safeCreatePermission({
		policy: calPolicyId,
		collection: 'locations',
		action: 'read',
		fields: ['*'],
		permissions: {},
		validation: {}
	});

	// directus_users: READ own profile (required for Directus app)
	await safeCreatePermission({
		policy: calPolicyId,
		collection: 'directus_users',
		action: 'read',
		fields: ['id', 'email', 'first_name', 'last_name', 'avatar', 'role'],
		permissions: { id: { _eq: '$CURRENT_USER' } },
		validation: {}
	});

	// =========================================================================
	// Done
	// =========================================================================
	console.log('');
	console.log('=== Permissions setup complete! ===');
	console.log('');
	console.log(`Static token for .env: DIRECTUS_STATIC_TOKEN=${STATIC_TOKEN}`);
	console.log(`For dev frontend .env: DIRECTUS_URL=http://localhost:8055`);
	console.log(`                       DIRECTUS_TOKEN=${STATIC_TOKEN}`);
	console.log('');
	console.log('Calendar role "Kalender" and policy "Kalender-Bearbeiter" are ready.');
	console.log('Assign individual users to the "Kalender" role via the Directus admin UI.');
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
