import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "STO.Flow 6.0 — Workshop Operations",
  description: "Операционная платформа автосервиса: CRM, заказ-наряды, запись, снабжение и финансы."
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return <html lang="ru"><body>{children}</body></html>;
}
