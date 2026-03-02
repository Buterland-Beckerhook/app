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

{#snippet autoIcon(cls: string)}
	<svg xmlns="http://www.w3.org/2000/svg" class={cls} viewBox="0 -960 960 960" fill="currentColor"
		><path
			d="M440-200q52 0 99-21t81-60q-128-8-214-99.5T320-600q0-13 1-25.5t3-24.5q-57 32-90.5 88T200-440q0 100 70 170t170 70Zm0 80q-134 0-227-93t-93-227q0-134 93-227t227-93q5 0 10 .5t10 .5q-29 32-44.5 73T400-600q0 100 70 170t170 70q31 0 60.5-7.5T756-390q-18 118-108 194t-208 76Zm112-400 128-360h80l128 360h-76l-28-80H656l-28 80h-76Zm122-134h92l-46-146-46 146ZM407-381Z"
		/></svg
	>
{/snippet}

{#snippet lightIcon(cls: string)}
	<svg xmlns="http://www.w3.org/2000/svg" class={cls} viewBox="0 -960 960 960" fill="currentColor"
		><path
			d="M565-395q35-35 35-85t-35-85q-35-35-85-35t-85 35q-35 35-35 85t35 85q35 35 85 35t85-35Zm-226.5 56.5Q280-397 280-480t58.5-141.5Q397-680 480-680t141.5 58.5Q680-563 680-480t-58.5 141.5Q563-280 480-280t-141.5-58.5ZM200-440H40v-80h160v80Zm720 0H760v-80h160v80ZM440-760v-160h80v160h-80Zm0 720v-160h80v160h-80ZM256-650l-101-97 57-59 96 100-52 56Zm492 496-97-101 53-55 101 97-57 59Zm-98-550 97-101 59 57-100 96-56-52ZM154-212l101-97 55 53-97 101-59-57Zm326-268Z"
		/></svg
	>
{/snippet}

{#snippet darkIcon(cls: string)}
	<svg xmlns="http://www.w3.org/2000/svg" class={cls} viewBox="0 -960 960 960" fill="currentColor"
		><path
			d="M480-120q-150 0-255-105T120-480q0-150 105-255t255-105q14 0 27.5 1t26.5 3q-41 29-65.5 75.5T444-660q0 90 63 153t153 63q55 0 101-24.5t75-65.5q2 13 3 26.5t1 27.5q0 150-105 255T480-120Zm0-80q88 0 158-48.5T740-375q-20 5-40 8t-40 3q-123 0-209.5-86.5T364-660q0-20 3-40t8-40q-78 32-126.5 102T200-480q0 116 82 198t198 82Zm-10-270Z"
		/></svg
	>
{/snippet}

{#if variant === 'full'}
	<!-- Full variant: icon + label, used in mobile menu -->
	<button
		onclick={cycle}
		class="flex items-center gap-2 text-sm text-gray-500 hover:text-primary dark:text-gray-400 dark:hover:text-primary"
		aria-label="Farbschema wechseln: {labels[theme]}"
	>
		{#if theme === 'auto'}
			{@render autoIcon('h-5 w-5')}
		{:else if theme === 'light'}
			{@render lightIcon('h-5 w-5')}
		{:else}
			{@render darkIcon('h-5 w-5')}
		{/if}
		<span>{labels[theme]}</span>
	</button>
{:else}
	<!-- Icon-only variant: used in desktop nav bar -->
	<button
		onclick={cycle}
		class="flex items-center text-gray-500 hover:text-primary dark:text-gray-400 dark:hover:text-primary"
		aria-label="Farbschema wechseln: {labels[theme]}"
		title={labels[theme]}
	>
		{#if theme === 'auto'}
			{@render autoIcon('h-5 w-5')}
		{:else if theme === 'light'}
			{@render lightIcon('h-5 w-5')}
		{:else}
			{@render darkIcon('h-5 w-5')}
		{/if}
	</button>
{/if}
