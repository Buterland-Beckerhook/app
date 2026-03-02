<script lang="ts">
	import { page } from '$app/state';
	import ThemeSwitch from '$lib/components/ThemeSwitch.svelte';
	import '../app.css';

	let { children } = $props();

	let menuOpen = $state(false);
	let openDropdown = $state<string | null>(null);

	// Close mobile menu on navigation
	$effect(() => {
		void page.url;
		menuOpen = false;
		openDropdown = null;
	});

	interface NavLink {
		href: string;
		label: string;
		children?: { href: string; label: string }[];
	}

	const navLinks: NavLink[] = [
		{ href: '/aktuell', label: 'Aktuelles' },
		{ href: '/termine', label: 'Termine' },
		{
			href: '/thron',
			label: 'Thron',
			children: [
				{ href: '/thron', label: 'Throne seit 1909' },
				{ href: '/aktuell/kaiserthron-2009', label: 'Kaiserthron 2009' },
				{ href: '/aktuell/kaiserthron-1984', label: 'Kaiserthron 1984' }
			]
		},
		{
			href: '/verein',
			label: 'Verein',
			children: [
				{ href: '/verein', label: 'Über uns' },
				{ href: '/verein/vorstand', label: 'Vorstand' },
				{ href: '/verein/offiziere', label: 'Offiziere' },
				{ href: '/verein/jungschuetzen', label: 'Jungschützen' },
				{ href: '/verein/kinderfest', label: 'Kinderfest' },
				{ href: '/verein/mitglied-werden', label: 'Mitglied werden' }
			]
		},
		{ href: '/kontakt', label: 'Kontakt' }
	];

	function toggleDropdown(label: string) {
		openDropdown = openDropdown === label ? null : label;
	}

	// Close desktop dropdown when clicking outside
	function handleClickOutside(event: MouseEvent) {
		const target = event.target as HTMLElement;
		if (!target.closest('.nav-dropdown')) {
			openDropdown = null;
		}
	}
</script>

<svelte:window onclick={handleClickOutside} />

<svelte:head>
	<link rel="icon" href="/favicon.ico" sizes="48x48" />
	<link rel="icon" href="/logo.svg" type="image/svg+xml" />
	<link rel="apple-touch-icon" href="/logo.svg" />
	<meta name="description" content="Schützenverein Buterland-Beckerhook e.V." />
</svelte:head>

<div class="flex min-h-screen flex-col bg-white text-gray-900 dark:bg-forest-green-950 dark:text-gray-200">
	<header class="border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
		<nav class="mx-auto flex max-w-6xl items-center justify-between px-4 py-2">
			<a href="/" class="flex items-center gap-3">
				<img src="/logo.svg" alt="" width="48" height="48" class="h-12 w-12 md:h-20 md:w-20" />
				<div class="font-logo leading-tight">
					<span class="block text-sm text-gray-600 dark:text-gray-400 md:text-xl"
						>Schützenverein</span
					>
					<span class="block text-xl text-primary md:text-3xl">Buterland-Beckerhook e.V.</span>
				</div>
			</a>

			<!-- Desktop nav -->
			<div class="hidden items-center gap-6 md:flex">
				{#each navLinks as link (link.href)}
					{#if link.children}
						<div class="nav-dropdown relative">
							<button
								class="flex items-center gap-1 text-gray-600 transition-colors hover:text-primary dark:text-gray-300 dark:hover:text-primary"
								onclick={(e) => {
									e.stopPropagation();
									toggleDropdown(link.label);
								}}
							>
								{link.label}
								<svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M19 9l-7 7-7-7"
									/>
								</svg>
							</button>
							{#if openDropdown === link.label}
								<div
									class="absolute left-0 top-full z-50 mt-2 min-w-48 rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-800"
								>
									{#each link.children as child (child.href)}
										<a
											href={child.href}
											class="block px-4 py-2 text-sm text-gray-600 transition-colors hover:bg-gray-50 hover:text-primary dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-primary"
										>
											{child.label}
										</a>
									{/each}
								</div>
							{/if}
						</div>
					{:else}
						<a
							href={link.href}
							class="text-gray-600 transition-colors hover:text-primary dark:text-gray-300 dark:hover:text-primary"
							>{link.label}</a
						>
					{/if}
				{/each}
				<ThemeSwitch />
			</div>

			<!-- Mobile hamburger -->
			<button
				class="flex items-center text-gray-600 dark:text-gray-300 md:hidden"
				aria-label="Menü öffnen"
				aria-expanded={menuOpen}
				onclick={() => (menuOpen = !menuOpen)}
			>
				{#if menuOpen}
					<!-- X icon -->
					<svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M6 18L18 6M6 6l12 12"
						/>
					</svg>
				{:else}
					<!-- Hamburger icon -->
					<svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M4 6h16M4 12h16M4 18h16"
						/>
					</svg>
				{/if}
			</button>
		</nav>

		<!-- Mobile menu -->
		{#if menuOpen}
			<div class="border-t border-gray-200 px-4 pb-4 dark:border-gray-700 md:hidden">
				{#each navLinks as link (link.href)}
					{#if link.children}
						<div>
							<button
								class="flex w-full items-center justify-between py-2 text-gray-600 hover:text-primary dark:text-gray-300 dark:hover:text-primary"
								onclick={() => toggleDropdown(link.label)}
							>
								{link.label}
								<svg
									class="h-4 w-4 transition-transform"
									class:rotate-180={openDropdown === link.label}
									fill="none"
									viewBox="0 0 24 24"
									stroke="currentColor"
								>
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M19 9l-7 7-7-7"
									/>
								</svg>
							</button>
							{#if openDropdown === link.label}
								<div class="border-l-2 border-gray-200 pl-4 dark:border-gray-700">
									{#each link.children as child (child.href)}
										<a
											href={child.href}
											class="block py-1.5 text-sm text-gray-600 hover:text-primary dark:text-gray-300 dark:hover:text-primary"
										>
											{child.label}
										</a>
									{/each}
								</div>
							{/if}
						</div>
					{:else}
						<a
							href={link.href}
							class="block py-2 text-gray-600 hover:text-primary dark:text-gray-300 dark:hover:text-primary"
							>{link.label}</a
						>
					{/if}
				{/each}
				<div class="mt-2 border-t border-gray-200 pt-3 dark:border-gray-700">
					<ThemeSwitch variant="full" />
				</div>
			</div>
		{/if}
	</header>

	<main class="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
		{@render children()}
	</main>

	<footer
		class="border-t border-gray-200 bg-gray-50 text-sm text-gray-500 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-400"
	>
		<div
			class="mx-auto flex max-w-6xl flex-col items-center gap-2 px-4 py-6 md:flex-row md:justify-between"
		>
			<p>&copy; {new Date().getFullYear()} Schützenverein Buterland-Beckerhook e.V.</p>
			<div class="flex gap-4">
				<a
					href="/impressum"
					class="text-gray-500 hover:text-primary dark:text-gray-400 dark:hover:text-primary"
					>Impressum</a
				>
				<a
					href="/datenschutz"
					class="text-gray-500 hover:text-primary dark:text-gray-400 dark:hover:text-primary"
					>Datenschutz</a
				>
			</div>
		</div>
	</footer>
</div>
