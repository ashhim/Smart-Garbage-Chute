import './globals.css';

export const metadata = {
  title: 'Smart Garbage Chute System',
  description: 'Control room dashboard',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}