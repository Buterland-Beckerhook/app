<script lang="ts">
	import { page } from '$app/state';
	import '../app.css';

	let { children } = $props();

	let menuOpen = $state(false);

	// Close mobile menu on navigation
	$effect(() => {
		void page.url;
		menuOpen = false;
	});

	const navLinks = [
		{ href: '/aktuell', label: 'Aktuell' },
		{ href: '/termine', label: 'Termine' },
		{ href: '/thron', label: 'Thron' },
		{ href: '/verein', label: 'Verein' },
		{ href: '/kontakt', label: 'Kontakt' }
	];
</script>

<svelte:head>
	<link rel="icon" href="/favicon.ico" sizes="48x48" />
	<link rel="icon" href="/logo.svg" type="image/svg+xml" />
	<link rel="apple-touch-icon" href="/logo.svg" />
	<meta name="description" content="Schützenverein Buterland-Beckerhook e.V." />
</svelte:head>

<div class="flex min-h-screen flex-col bg-white text-gray-900 dark:bg-gray-900 dark:text-gray-100">
	<header class="bg-primary text-white">
		<nav class="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
			<a href="/" class="flex items-center gap-3">
				<img src="/logo.svg" alt="" width="40" height="40" class="h-10 w-10" />
				<span class="font-logo text-xl font-bold">Buterland-Beckerhook</span>
			</a>

			<!-- Desktop nav -->
			<div class="hidden gap-6 md:flex">
				{#each navLinks as link (link.href)}
					<a href={link.href} class="hover:underline">{link.label}</a>
				{/each}
			</div>

			<!-- Mobile hamburger -->
			<button
				class="flex items-center md:hidden"
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
			<div class="border-t border-white/20 px-4 pb-4 md:hidden">
				{#each navLinks as link (link.href)}
					<a href={link.href} class="block py-2 hover:underline">{link.label}</a>
				{/each}
			</div>
		{/if}
	</header>

	<main class="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
		{@render children()}
	</main>

	<footer class="bg-gray-100 text-sm text-gray-600 dark:bg-gray-800 dark:text-gray-400">
		<div
			class="mx-auto flex max-w-6xl flex-col items-center gap-2 px-4 py-6 md:flex-row md:justify-between"
		>
			<p>&copy; {new Date().getFullYear()} Schützenverein Buterland-Beckerhook e.V.</p>
			<div class="flex gap-4">
				<a href="/impressum" class="hover:underline">Impressum</a>
				<a href="/datenschutz" class="hover:underline">Datenschutz</a>
			</div>
		</div>
	</footer>
</div>
