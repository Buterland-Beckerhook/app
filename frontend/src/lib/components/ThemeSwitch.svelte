<script lang="ts">
	import { browser } from '$app/environment';

	type Theme = 'auto' | 'light' | 'dark';
	const themes: Theme[] = ['auto', 'light', 'dark'];
	const labels: Record<Theme, string> = {
		auto: 'Automatisch',
		light: 'Hell',
		dark: 'Dunkel'
	};

	let { variant = 'icon' }: { variant?: 'icon' | 'full' } = $props();

	let theme = $state<Theme>('auto');

	function getSystemPrefersDark(): boolean {
		return browser && window.matchMedia('(prefers-color-scheme: dark)').matches;
	}

	function applyTheme(t: Theme) {
		if (!browser) return;
		const isDark = t === 'dark' || (t === 'auto' && getSystemPrefersDark());
		document.documentElement.classList.toggle('dark', isDark);
	}

	function cycle() {
		const idx = themes.indexOf(theme);
		theme = themes[(idx + 1) % themes.length];
		if (browser) {
			localStorage.setItem('theme', theme);
		}
		applyTheme(theme);
	}

	// Initialize from localStorage
	$effect(() => {
		if (!browser) return;
		const stored = localStorage.getItem('theme') as Theme | null;
		if (stored && themes.includes(stored)) {
			theme = stored;
		}
		applyTheme(theme);

		// Listen for OS theme changes (relevant in auto mode)
		const mq = window.matchMedia('(prefers-color-scheme: dark)');
		const handler = () => applyTheme(theme);
		mq.addEventListener('change', handler);
		return () => mq.removeEventListener('change', handler);
	});
</script>

{#if variant === 'full'}
	<!-- Full variant: icon + label, used in mobile menu -->
	<button
		onclick={cycle}
		class="flex items-center gap-2 text-sm text-white/80 hover:text-white"
		aria-label="Farbschema wechseln: {labels[theme]}"
	>
		{#if theme === 'auto'}
			<!-- Monitor icon -->
			<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
				/>
			</svg>
		{:else if theme === 'light'}
			<!-- Sun icon -->
			<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.95 7.95l-.71-.71M4.05 4.05l-.71-.71M16 12a4 4 0 11-8 0 4 4 0 018 0z"
				/>
			</svg>
		{:else}
			<!-- Moon icon -->
			<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z"
				/>
			</svg>
		{/if}
		<span>{labels[theme]}</span>
	</button>
{:else}
	<!-- Icon-only variant: used in desktop nav bar -->
	<button
		onclick={cycle}
		class="flex items-center hover:text-white/80"
		aria-label="Farbschema wechseln: {labels[theme]}"
		title={labels[theme]}
	>
		{#if theme === 'auto'}
			<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
				/>
			</svg>
		{:else if theme === 'light'}
			<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.95 7.95l-.71-.71M4.05 4.05l-.71-.71M16 12a4 4 0 11-8 0 4 4 0 018 0z"
				/>
			</svg>
		{:else}
			<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					d="M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z"
				/>
			</svg>
		{/if}
	</button>
{/if}
