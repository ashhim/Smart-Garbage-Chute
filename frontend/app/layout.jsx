import './globals.css';

export const metadata = {
  title: 'Smart Garbage Chute System | Industrial Monitoring Dashboard',
  description: 'Smart Garbage Chute Room Monitoring & Detection System for centralized IoT and AI operations.',
  keywords: [
    'smart garbage chute',
    'iot monitoring',
    'ai cctv',
    'esp32 poe',
    'industrial dashboard',
  ],
  robots: {
    index: false,
    follow: false,
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="min-h-screen bg-slate-950 text-slate-100 antialiased">
        {children}
      </body>
    </html>
  );
}