import { createHandler } from './handler.mjs';
import nodemailer, {type SendMailOptions} from 'npm:nodemailer@10.1.0';

const sendMail = async (message: SendMailOptions, config: {smtpHost: string; smtpPort: number; smtpUser: string; smtpPassword: string}) => {
  if (![465, 2525, 2587].includes(config.smtpPort)) throw new Error('Use a TLS SMTP port allowed by Supabase Edge Functions');
  const transport = nodemailer.createTransport({
    host: config.smtpHost, port: config.smtpPort, secure: config.smtpPort === 465,
    requireTLS: true, auth: {user: config.smtpUser, pass: config.smtpPassword},
    connectionTimeout: 15000, greetingTimeout: 15000, socketTimeout: 20000,
    tls: {rejectUnauthorized: true, minVersion: 'TLSv1.2'},
    disableFileAccess: true, disableUrlAccess: true,
  });
  try { return await transport.sendMail(message); } finally { transport.close(); }
};

Deno.serve(createHandler((name: string) => Deno.env.get(name), fetch, sendMail));
